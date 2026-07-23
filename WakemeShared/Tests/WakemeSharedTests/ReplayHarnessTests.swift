import XCTest
@testable import WakemeShared

final class ReplayHarnessTests: XCTestCase {

    // Build a CalibrationData with known baselines for a deterministic heuristic.
    private func makeCalibration() -> CalibrationData {
        let cal = CalibrationData()
        cal.restingHR = 60
        cal.restingHRV = 40
        cal.sleepHR = 48
        cal.motionBaseline = 0.5
        cal.motionBaselineSamples = 30   // makes motionBaselineReady true, effectiveMotion non-nil
        return cal
    }

    // A vector representing an ATTACK: motion well below baseline, HR below RHR, HRV above baseline.
    private func attackVector(at t: Date) -> FeatureVector {
        FeatureVector(
            timestamp: t,
            heartRate: 50, hrv: 55,
            meanAccelMagnitude: 0.05, peakAccelMagnitude: 0.1, gyroMagnitude: 0.02,
            baselineHR: 60, baselineHRV: 40, baselineAccel: 0.5,
            hrTrend: -10, hrvTrend: 15, accelTrend: -0.45,
            activityContext: .stationary
        )
    }

    // A NORMAL vector: motion at baseline, HR at rest, HRV at baseline.
    private func normalVector(at t: Date) -> FeatureVector {
        FeatureVector(
            timestamp: t,
            heartRate: 65, hrv: 40,
            meanAccelMagnitude: 0.5, peakAccelMagnitude: 0.6, gyroMagnitude: 0.3,
            baselineHR: 60, baselineHRV: 40, baselineAccel: 0.5,
            hrTrend: 2, hrvTrend: 0, accelTrend: 0,
            activityContext: .stationary
        )
    }

    func testHarnessDetectsAttackCluster() {
        UserDefaults.standard.set(3.0, forKey: "sensitivityLevel")  // medium
        let strategy = HeuristicStrategy(calibration: makeCalibration())

        let base = Date()
        var vectors: [FeatureVector] = []
        // 10 normal vectors
        for i in 0..<10 { vectors.append(normalVector(at: base.addingTimeInterval(Double(i) * 2))) }
        // then 4 consecutive attack vectors (enough for a 3-in-a-row fire)
        let markerTime = base.addingTimeInterval(22)
        for i in 0..<4 { vectors.append(attackVector(at: base.addingTimeInterval(22 + Double(i) * 2))) }

        let input = ReplayHarness.ReplayInput(vectors: vectors, markers: [markerTime])
        let result = ReplayHarness().run(input: input, strategy: strategy, threshold: 0.60)

        XCTAssertGreaterThan(result.recall, 0, "Expected at least one detection near the marker")
        XCTAssertGreaterThan(result.fired.count, 0)
    }

    func testHarnessDoesNotFireOnAllNormal() {
        UserDefaults.standard.set(3.0, forKey: "sensitivityLevel")
        let strategy = HeuristicStrategy(calibration: makeCalibration())
        let base = Date()
        let vectors = (0..<20).map { normalVector(at: base.addingTimeInterval(Double($0) * 2)) }
        let input = ReplayHarness.ReplayInput(vectors: vectors, markers: [])
        let result = ReplayHarness().run(input: input, strategy: strategy, threshold: 0.60)
        XCTAssertEqual(result.fired.count, 0, "Should not fire on entirely normal data")
    }
}
