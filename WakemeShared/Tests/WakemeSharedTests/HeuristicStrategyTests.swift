import Testing
import SwiftData
@testable import WakemeShared

@Suite("HeuristicStrategy")
struct HeuristicStrategyTests {

    // Shared helper: build a CalibrationData seeded with known baselines in an in-memory container.
    @MainActor
    private func makeCalibration() throws -> (CalibrationData, ModelContext) {
        let container = try ModelContainer.makeWakemePreviewContainer()
        let context = ModelContext(container)

        let calibration = CalibrationData()
        calibration.restingHR = 60          // effectiveRHR = 60
        calibration.restingHRV = 40         // effectiveHRV = 40
        calibration.sleepHR = 50
        calibration.motionBaseline = 0.5    // effectiveMotion = 0.5
        calibration.motionBaselineSamples = 30  // motionBaselineReady == true
        context.insert(calibration)

        return (calibration, context)
    }

    @Test("Attack-signature vector scores > 0.6")
    @MainActor
    func attackVectorScoresHigh() throws {
        let (calibration, _) = try makeCalibration()
        let strategy = HeuristicStrategy(calibration: calibration)

        // HR well below RHR, HRV well above baseline, motion nearly zero
        let vector = FeatureVector(
            timestamp: Date(),
            heartRate: 52,
            hrv: 55,
            meanAccelMagnitude: 0.1,
            peakAccelMagnitude: 0.12,
            gyroMagnitude: 0.04,
            baselineHR: 60,
            baselineHRV: 40,
            baselineAccel: 0.5,
            hrTrend: -8,
            hrvTrend: 15,
            accelTrend: -0.4,
            activityContext: .stationary
        )

        // Expected: motion +0.45, HR +0.30, HRV +0.25 → capped at 1.0
        #expect(strategy.evaluate(vector) > 0.6)
    }

    @Test("Normal-activity vector scores < 0.2")
    @MainActor
    func normalVectorScoresLow() throws {
        let (calibration, _) = try makeCalibration()
        let strategy = HeuristicStrategy(calibration: calibration)

        // HR above RHR, HRV at baseline, motion at baseline — nothing anomalous
        let vector = FeatureVector(
            timestamp: Date(),
            heartRate: 70,
            hrv: 40,
            meanAccelMagnitude: 0.5,
            peakAccelMagnitude: 0.6,
            gyroMagnitude: 0.3,
            baselineHR: 60,
            baselineHRV: 40,
            baselineAccel: 0.5,
            hrTrend: 10,
            hrvTrend: 0,
            accelTrend: 0,
            activityContext: .stationary
        )

        // All signals at or above baseline → score = 0.0
        #expect(strategy.evaluate(vector) < 0.2)
    }

    @Test("Returns 0.0 when no baselines are set")
    @MainActor
    func noBaselineReturnsZero() throws {
        let container = try ModelContainer.makeWakemePreviewContainer()
        let context = ModelContext(container)
        let calibration = CalibrationData()   // all optionals nil, motionBaselineSamples = 0
        context.insert(calibration)

        let strategy = HeuristicStrategy(calibration: calibration)

        let vector = FeatureVector(
            timestamp: Date(),
            heartRate: 52,
            hrv: 55,
            meanAccelMagnitude: 0.1,
            peakAccelMagnitude: 0.12,
            gyroMagnitude: 0.04,
            baselineHR: 60,
            baselineHRV: 40,
            baselineAccel: 0.5,
            hrTrend: -8,
            hrvTrend: 15,
            accelTrend: -0.4,
            activityContext: .unknown
        )

        #expect(strategy.evaluate(vector) == 0.0)
    }
}
