import Foundation
import HealthKit
import CoreMotion
import UserNotifications
import Observation

@Observable
@MainActor
final class PermissionManager {

    var healthKitGranted: Bool = false
    var motionGranted: Bool = false
    var notificationsGranted: Bool = false

    private let store = HKHealthStore()
    private let motionActivityManager = CMMotionActivityManager()

    private var healthReadTypes: Set<HKObjectType> {
        [
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.walkingHeartRateAverage),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    func requestHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: healthReadTypes)
        // HealthKit never reveals read authorization status, so treat "asked" as done.
        // Whether data actually flows is validated by HealthKitBaselineManager returning non-nil values.
        healthKitGranted = true
    }

    func requestMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // Starting updates triggers the system permission prompt on the first call.
            motionActivityManager.startActivityUpdates(to: .main) { [weak self] _ in
                self?.motionActivityManager.stopActivityUpdates()
                Task { @MainActor in
                    self?.motionGranted = (CMMotionActivityManager.authorizationStatus() == .authorized)
                    cont.resume()
                }
            }
        }
    }

    func requestNotifications() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationsGranted = granted
    }
}
