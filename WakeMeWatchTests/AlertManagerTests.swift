import XCTest
import WakemeShared
// To run: add this file to the WakeMeWatchTests unit testing bundle target.
@testable import WakeMeWatch_Watch_App

@MainActor
final class AlertManagerTests: XCTestCase {

    // @MainActor so its stored properties are main-actor isolated, matching the protocol requirements.
    @MainActor
    final class MockOutput: AlertOutput {
        var haptics: [Int] = []
        var alarms: [Bool] = []
        var confirmations = 0

        func haptic(stage: Int) { haptics.append(stage) }
        func alarm(subtle: Bool) { alarms.append(subtle) }
        func confirmation() { confirmations += 1 }
    }

    private func makeEvent(context: ActivityContext = .stationary) -> DetectionEvent {
        let v = FeatureVector(
            timestamp: Date(), heartRate: 50, hrv: 55,
            meanAccelMagnitude: 0.05, peakAccelMagnitude: 0.1, gyroMagnitude: 0.02,
            baselineHR: 60, baselineHRV: 40, baselineAccel: 0.5,
            hrTrend: -10, hrvTrend: 15, accelTrend: -0.45,
            activityContext: context
        )
        return DetectionEvent(
            timestamp: Date(), triggeringVector: v, confidence: 0.9,
            mode: .active, activityContext: context
        )
    }

    func testDetectionEntersEscalatingStage1() {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.handleDetection(makeEvent())
        if case .escalating(let stage, _) = mgr.alertState {
            XCTAssertEqual(stage, 1)
        } else {
            XCTFail("expected escalating(stage: 1), got \(mgr.alertState)")
        }
        XCTAssertEqual(out.haptics, [1])
    }

    func testSecondDetectionIsDebounced() {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.handleDetection(makeEvent())
        mgr.handleDetection(makeEvent())   // should be ignored while already escalating
        XCTAssertEqual(out.haptics, [1], "Only one stage-1 haptic should fire")
    }

    func testDrivingContextDoesNotAlert() {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.handleDetection(makeEvent(context: .automotive))
        XCTAssertEqual(mgr.alertState, .idle)
        XCTAssertTrue(out.haptics.isEmpty)
    }

    func testDismissGoesToDismissedThenIdle() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.handleDetection(makeEvent())
        mgr.dismiss(as: .confirmedAttack)
        if case .dismissed(let t, _) = mgr.alertState {
            XCTAssertEqual(t, .confirmedAttack)
        } else {
            XCTFail("expected dismissed, got \(mgr.alertState)")
        }
        XCTAssertEqual(out.confirmations, 1)
        try await Task.sleep(for: .seconds(2.2))
        XCTAssertEqual(mgr.alertState, .idle)
    }

    func testHapticOnlyCeilingNeverReachesStage4() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.stageInterval = .milliseconds(20)
        mgr.noResponseGrace = .milliseconds(20)
        // Use the test seam to inject .hapticOnly ceiling without needing SensorCoordinator.
        mgr.handleDetection(makeEvent(), ceiling: .hapticOnly)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(out.alarms.isEmpty, "hapticOnly ceiling must never play an alarm")
    }

    func testFullAlarmReachesStage4() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.stageInterval = .milliseconds(20)
        mgr.noResponseGrace = .seconds(5)   // long enough we don't auto-dismiss during the test
        // No session → default ceiling .fullAlarm
        mgr.handleDetection(makeEvent(), ceiling: .fullAlarm)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(out.alarms, [false], "fullAlarm should play a non-subtle alarm at stage 4")
    }

    func testSilentCeilingNeverEscalates() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.stageInterval = .milliseconds(20)
        mgr.noResponseGrace = .milliseconds(20)
        mgr.handleDetection(makeEvent(), ceiling: .silent)
        try await Task.sleep(for: .milliseconds(200))
        // Only stage 1 haptic fires from startEscalation(); all subsequent stages blocked.
        XCTAssertEqual(out.haptics, [1])
        XCTAssertTrue(out.alarms.isEmpty)
    }

    func testNoResponseAutoDismisses() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.stageInterval = .milliseconds(10)
        mgr.noResponseGrace = .milliseconds(10)
        mgr.handleDetection(makeEvent(), ceiling: .hapticOnly)
        try await Task.sleep(for: .milliseconds(300))
        if case .dismissed(let t, _) = mgr.alertState {
            XCTAssertEqual(t, .noResponse)
        } else {
            XCTFail("expected noResponse auto-dismiss, got \(mgr.alertState)")
        }
        XCTAssertEqual(out.confirmations, 1)
    }

    func testDismissBeforeEscalationCancelsTask() async throws {
        let out = MockOutput()
        let mgr = AlertManager(output: out)
        mgr.stageInterval = .seconds(30)   // would take 30 s to escalate naturally
        mgr.handleDetection(makeEvent())
        XCTAssertEqual(out.haptics, [1])
        mgr.dismiss(as: .falseAlarm)
        try await Task.sleep(for: .milliseconds(50))
        // Only one haptic (stage 1) should ever fire; no further escalation after dismiss.
        XCTAssertEqual(out.haptics, [1])
    }
}
