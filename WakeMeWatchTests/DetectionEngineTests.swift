import XCTest
import WakemeShared
// Module name is "WakeMeWatch_Watch_App" — Xcode converts spaces to underscores.
// To run: add this file to the WakeMeWatchTests unit testing bundle target.
@testable import WakeMeWatch_Watch_App

// Minimal stub strategy — returns a fixed confidence value set before each call.
private struct StubStrategy: DetectionStrategy {
    let version = 0
    var next: Double
    func evaluate(_ vector: FeatureVector) -> Double { next }
}

@MainActor
final class DetectionEngineTests: XCTestCase {

    private func makeVector(context: ActivityContext = .stationary) -> FeatureVector {
        FeatureVector(
            timestamp: Date(),
            heartRate: 55,
            hrv: 50,
            meanAccelMagnitude: 0.05,
            peakAccelMagnitude: 0.1,
            gyroMagnitude: 0.02,
            baselineHR: 65,
            baselineHRV: 40,
            baselineAccel: 0.5,
            hrTrend: -10,
            hrvTrend: 10,
            accelTrend: -0.45,
            activityContext: context
        )
    }

    // Fresh engine for each test — avoids shared-singleton state bleeding between tests.
    private func freshEngine(threshold: Double = 0.5) -> DetectionEngine {
        let engine = DetectionEngine.shared
        engine.resetBuffer()
        UserDefaults.standard.set(threshold, forKey: "thresholdPassive")
        UserDefaults.standard.set(threshold, forKey: "thresholdActive")
        return engine
    }

    // MARK: - No strategy

    func testNoStrategyIsNoOp() {
        let engine = freshEngine()
        // Do NOT install a strategy
        engine.process(makeVector(), mode: .passive)
        XCTAssertEqual(engine.currentConfidence, 0)
        XCTAssertFalse(engine.isArmed)
        XCTAssertFalse(engine.hasStrategy)
    }

    // MARK: - Confirmation window

    func testOneHighVectorDoesNotFire() {
        let engine = freshEngine(threshold: 0.5)
        var fired = false
        engine.onDetectionEvent = { _ in fired = true }
        engine.install(strategy: StubStrategy(next: 1.0))

        engine.process(makeVector(), mode: .passive)

        XCTAssertFalse(fired, "Should not fire on a single high sample")
    }

    func testTwoHighVectorsSetsArmedButDoesNotFire() {
        let engine = freshEngine(threshold: 0.5)
        var fired = false
        engine.onDetectionEvent = { _ in fired = true }
        engine.install(strategy: StubStrategy(next: 1.0))

        engine.process(makeVector(), mode: .passive)
        engine.process(makeVector(), mode: .passive)

        XCTAssertTrue(engine.isArmed, "Should be armed after 2 high samples")
        XCTAssertFalse(fired, "Should not fire until 3 consecutive samples")
    }

    func testThreeHighVectorsFires() {
        let engine = freshEngine(threshold: 0.5)
        var eventCount = 0
        engine.onDetectionEvent = { _ in eventCount += 1 }
        engine.install(strategy: StubStrategy(next: 1.0))

        engine.process(makeVector(), mode: .passive)
        engine.process(makeVector(), mode: .passive)
        engine.process(makeVector(), mode: .passive)

        XCTAssertEqual(eventCount, 1, "Should fire exactly once on 3 consecutive high samples")
    }

    func testFourthHighAfterFireDoesNotRefire() {
        let engine = freshEngine(threshold: 0.5)
        var eventCount = 0
        engine.onDetectionEvent = { _ in eventCount += 1 }
        engine.install(strategy: StubStrategy(next: 1.0))

        for _ in 0..<4 {
            engine.process(makeVector(), mode: .passive)
        }

        XCTAssertEqual(eventCount, 1, "Buffer cleared after fire — 4th vector should not re-fire")
        XCTAssertFalse(engine.isArmed)
    }

    func testLowVectorBetweenHighsPreventsConfirmation() {
        let engine = freshEngine(threshold: 0.5)
        var fired = false
        engine.onDetectionEvent = { _ in fired = true }

        engine.install(strategy: StubStrategy(next: 1.0))
        engine.process(makeVector(), mode: .passive)
        engine.process(makeVector(), mode: .passive)

        // Break the run with a low confidence
        engine.install(strategy: StubStrategy(next: 0.1))
        engine.process(makeVector(), mode: .passive)

        XCTAssertFalse(fired, "Run broken by low sample — should not fire")
    }

    // MARK: - Context policy

    func testAutomotiveContextNeverFires() {
        let engine = freshEngine(threshold: 0.5)
        var fired = false
        engine.onDetectionEvent = { _ in fired = true }
        engine.install(strategy: StubStrategy(next: 1.0))

        for _ in 0..<5 {
            engine.process(makeVector(context: .automotive), mode: .active)
        }

        XCTAssertFalse(fired, "Automotive context must never fire the detection event")
        XCTAssertFalse(engine.isArmed)
        XCTAssertEqual(engine.currentConfidence, 0)
    }

    // MARK: - Threshold modes

    func testActiveModeUsesLowerThreshold() {
        // Active threshold is 0.5; passive is 0.9. A confidence of 0.6 should only fire in active.
        UserDefaults.standard.set(0.9, forKey: "thresholdPassive")
        UserDefaults.standard.set(0.5, forKey: "thresholdActive")

        let engine = DetectionEngine.shared
        engine.resetBuffer()
        var eventCount = 0
        engine.onDetectionEvent = { _ in eventCount += 1 }
        engine.install(strategy: StubStrategy(next: 0.6))

        for _ in 0..<3 { engine.process(makeVector(), mode: .active) }
        XCTAssertEqual(eventCount, 1, "0.6 confidence should confirm in active mode (threshold 0.5)")

        engine.resetBuffer()
        eventCount = 0
        for _ in 0..<3 { engine.process(makeVector(), mode: .passive) }
        XCTAssertEqual(eventCount, 0, "0.6 confidence should NOT confirm in passive mode (threshold 0.9)")
    }
}
