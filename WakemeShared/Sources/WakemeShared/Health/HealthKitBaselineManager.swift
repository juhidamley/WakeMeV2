import Foundation
import HealthKit
import Observation

@Observable
@MainActor
public final class HealthKitBaselineManager {

    public static let shared = HealthKitBaselineManager()

    public var isQuerying: Bool = false
    public var lastError: String?

    private let store = HKHealthStore()

    private init() {}

    // MARK: - Public API

    /// Queries HealthKit for the user's baselines and writes them into `calibration`.
    /// Safe to call on first launch and on a weekly refresh.
    /// Note: HealthKit never reveals read-authorization status, so if the user denied
    /// access these queries simply return nil rather than an error — the app then falls
    /// back to on-device / generic values.
    public func refreshBaselines(calibration: CalibrationData) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "Health data is not available on this device."
            return
        }

        isQuerying = true
        lastError = nil
        defer { isQuerying = false }

        // Run the independent quantity queries concurrently
        async let rhr    = queryMostRecentSample(
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit(from: "count/min")
        )
        async let hrv    = queryMostRecentSample(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli)
        )
        async let active = queryMostRecentSample(
            type: HKQuantityType(.walkingHeartRateAverage),
            unit: HKUnit(from: "count/min")
        )
        async let sleep  = querySleepHR()

        let (rhrValue, hrvValue, activeValue, sleepValue) = await (rhr, hrv, active, sleep)

        calibration.restingHR  = rhrValue
        calibration.restingHRV = hrvValue
        calibration.activeHR   = activeValue
        calibration.sleepHR    = sleepValue
        calibration.healthKitLastQueried = Date()
        calibration.lastUpdated = Date()
    }

    // MARK: - Quantity queries

    /// Most recent sample of a quantity type over the last 90 days.
    private func queryMostRecentSample(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -90, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { [weak self] _, samples, error in
                self?.recordError(error)
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep HR derivation

    /// Mean heart rate during actual asleep periods over the last 30 days.
    /// Filters out "in bed" and "awake" sleep-analysis samples so only true sleep counts.
    private func querySleepHR() async -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let sleepPredicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: sleepPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [weak self] _, samples, error in
                self?.recordError(error)
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        // Keep only genuine "asleep" stages
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let asleepSamples = sleepSamples.filter { asleepValues.contains($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        // Collect HR samples within each sleep window (cap at 30 windows for cost)
        var allHRValues: [Double] = []
        for sample in asleepSamples.prefix(30) {
            let hrPredicate = HKQuery.predicateForSamples(
                withStart: sample.startDate,
                end: sample.endDate
            )
            let hrSamples: [HKQuantitySample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(
                    sampleType: HKQuantityType(.heartRate),
                    predicate: hrPredicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { [weak self] _, samples, error in
                    self?.recordError(error)
                    cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
                }
                store.execute(q)
            }
            allHRValues.append(
                contentsOf: hrSamples.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) }
            )
        }

        guard !allHRValues.isEmpty else { return nil }
        return allHRValues.reduce(0, +) / Double(allHRValues.count)
    }

    // MARK: - Error capture

    /// Callable from background query completion handlers. Schedules the update on the main actor.
    nonisolated private func recordError(_ error: Error?) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
        }
    }
}
