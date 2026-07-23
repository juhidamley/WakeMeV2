import Foundation
import HealthKit
import CoreMotion
import Observation
import WakemeShared

@Observable
@MainActor
public final class ActiveSessionManager {

    public private(set) var isRunning: Bool = false

    /// Called on the main actor every ~2s with a fresh FeatureVector.
    @ObservationIgnored
    public var onFeatureVector: (@MainActor (FeatureVector) -> Void)?

    // HealthKit / workout
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var hrQuery: HKAnchoredObjectQuery?

    // Motion
    @ObservationIgnored private let motionManager = CMMotionManager()

    // Rolling state (main-actor isolated)
    @ObservationIgnored private var baseline = BaselineTracker()
    @ObservationIgnored private var accelMags: [Double] = []   // magnitudes since last emit
    @ObservationIgnored private var gyroMags: [Double] = []
    @ObservationIgnored private var recentHRSamples: [Double] = []  // last N HR values for HRV approx
    @ObservationIgnored private var latestHR: Double = 0
    @ObservationIgnored private var emitTimer: Timer?

    public init() {}

    // MARK: - Lifecycle

    public func start(activityContext: ActivityContext) async throws {
        guard !isRunning else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown

        workoutSession = try HKWorkoutSession(healthStore: store, configuration: config)
        builder = workoutSession?.associatedWorkoutBuilder()
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)

        workoutSession?.startActivity(with: Date())
        try await builder?.beginCollection(at: Date())

        startMotion()
        startHRQuery()

        // Emit on the main run loop; the closure is already main-actor isolated.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emitVector(context: activityContext) }
        }
        RunLoop.main.add(timer, forMode: .common)
        emitTimer = timer

        isRunning = true
    }

    public func stop() async {
        emitTimer?.invalidate()
        emitTimer = nil

        motionManager.stopDeviceMotionUpdates()

        if let hrQuery { store.stop(hrQuery) }
        hrQuery = nil

        try? await builder?.endCollection(at: Date())
        try? await builder?.finishWorkout()
        workoutSession?.end()

        workoutSession = nil
        builder = nil
        accelMags.removeAll()
        gyroMags.removeAll()
        recentHRSamples.removeAll()
        isRunning = false
    }

    // MARK: - Motion

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1  // 10 Hz
        // Deliver on a background queue, then hop to main actor to mutate buffers safely.
        let queue = OperationQueue()
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let m = motion else { return }
            let accelMag = sqrt(m.userAcceleration.x * m.userAcceleration.x
                              + m.userAcceleration.y * m.userAcceleration.y
                              + m.userAcceleration.z * m.userAcceleration.z)
            let gyroMag = sqrt(m.rotationRate.x * m.rotationRate.x
                             + m.rotationRate.y * m.rotationRate.y
                             + m.rotationRate.z * m.rotationRate.z)
            Task { @MainActor [weak self] in
                self?.accelMags.append(accelMag)
                self?.gyroMags.append(gyroMag)
            }
        }
    }

    // MARK: - Heart rate

    private func startHRQuery() {
        let hrType = HKQuantityType(.heartRate)
        // Only samples from now forward — avoids replaying historical data.
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)

        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void
            = { [weak self] _, samples, _, _, _ in
                guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }
                let unit = HKUnit(from: "count/min")
                let values = quantitySamples.map { $0.quantity.doubleValue(for: unit) }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let latest = values.last { self.latestHR = latest }
                    self.recentHRSamples.append(contentsOf: values)
                    // Keep only the last ~30 samples for the HRV approximation
                    if self.recentHRSamples.count > 30 {
                        self.recentHRSamples.removeFirst(self.recentHRSamples.count - 30)
                    }
                }
            }

        let query = HKAnchoredObjectQuery(type: hrType, predicate: predicate, anchor: nil,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        hrQuery = query
    }

    /// Rough SDNN-style HRV from the standard deviation of recent HR samples.
    /// This is an APPROXIMATION — real SDNN needs beat-to-beat intervals, which the live
    /// workout stream doesn't expose. Good enough as a relative trend signal; do not present
    /// as a clinical HRV value.
    private func approximateHRV() -> Double {
        guard recentHRSamples.count >= 3 else { return 0 }
        let mean = recentHRSamples.reduce(0, +) / Double(recentHRSamples.count)
        let variance = recentHRSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recentHRSamples.count)
        return sqrt(variance)
    }

    // MARK: - Emit

    private func emitVector(context: ActivityContext) {
        // Need at least some motion data since the last emit.
        guard !accelMags.isEmpty else { return }

        let meanAccel = accelMags.reduce(0, +) / Double(accelMags.count)
        let peakAccel = accelMags.max() ?? 0
        let meanGyro = gyroMags.isEmpty ? 0 : gyroMags.reduce(0, +) / Double(gyroMags.count)
        accelMags.removeAll(keepingCapacity: true)
        gyroMags.removeAll(keepingCapacity: true)

        let hrv = approximateHRV()
        baseline.update(hr: latestHR > 0 ? latestHR : nil,
                        hrv: hrv > 0 ? hrv : nil,
                        accel: meanAccel)

        // Emit as soon as we have enough MOTION data. HR/HRV baselines fill in as they arrive;
        // downstream (heuristic) already guards on missing baselines and simply won't fire early.
        guard baseline.hasEnoughMotionData else { return }

        let vector = FeatureVector(
            timestamp: Date(),
            heartRate: latestHR,
            hrv: hrv,
            meanAccelMagnitude: meanAccel,
            peakAccelMagnitude: peakAccel,
            gyroMagnitude: meanGyro,
            baselineHR: baseline.baselineHR,
            baselineHRV: baseline.baselineHRV,
            baselineAccel: baseline.baselineAccel,
            hrTrend: baseline.hrTrend,
            hrvTrend: baseline.hrvTrend,
            accelTrend: baseline.accelTrend,
            activityContext: context
        )
        onFeatureVector?(vector)
    }
}
