import Foundation
import SwiftData

@Model public final class CalibrationData {

    // MARK: – Identity
    @Attribute(.unique) public var id: UUID

    // MARK: – HealthKit-sourced baselines (queried on launch, refreshed weekly)
    public var restingHR: Double?           // HKQuantityType.restingHeartRate
    public var restingHRV: Double?          // HKQuantityType.heartRateVariabilitySDNN
    public var sleepHR: Double?             // Derived: mean HR during sleep analysis periods
    public var activeHR: Double?            // HKQuantityType.walkingHeartRateAverage
    public var healthKitLastQueried: Date?

    // MARK: – Motion baseline (on-device; no HealthKit equivalent)
    public var motionBaseline: Double?      // Rolling mean accel magnitude, stationary waking
    public var motionBaselineSamples: Int   // Number of 2-second samples collected

    // MARK: – User overrides (nil = use computed value)
    public var userOverrideRHR: Double?
    public var userOverrideHRV: Double?
    public var userOverrideMotion: Double?

    // MARK: – Metadata
    public var lastUpdated: Date

    public init() {
        self.id = UUID()
        self.motionBaselineSamples = 0
        self.lastUpdated = Date()
    }

    // MARK: – Computed (not stored)
    public var motionBaselineReady: Bool { motionBaselineSamples >= 30 }

    public var effectiveRHR: Double?    { userOverrideRHR    ?? restingHR }
    public var effectiveHRV: Double?    { userOverrideHRV    ?? restingHRV }
    public var effectiveMotion: Double? { userOverrideMotion ?? motionBaseline }

    /// True when there is enough data for detection to start
    public var isReady: Bool {
        effectiveRHR != nil && motionBaselineReady
    }
}
