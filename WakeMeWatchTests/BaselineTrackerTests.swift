import XCTest
// Module name is "WakeMeWatch_Watch_App" — Xcode converts spaces to underscores.
// To run: add a watchOS Unit Testing Bundle target named "WakeMeWatchTests" in Xcode,
// set its Host Application to "WakeMeWatch Watch App", and add this file to it.
@testable import WakeMeWatch_Watch_App

final class BaselineTrackerTests: XCTestCase {

    func testEmptyStateReturnsZeroBaselinesAndTrends() {
        let t = BaselineTracker()
        XCTAssertEqual(t.baselineHR, 0)
        XCTAssertEqual(t.baselineAccel, 0)
        XCTAssertEqual(t.hrTrend, 0)
        XCTAssertFalse(t.hasEnoughData)
    }

    func testMeanIsCorrect() {
        let t = BaselineTracker()
        for v in [60.0, 62, 64] { t.update(hr: v, hrv: 40, accel: 0.5) }
        XCTAssertEqual(t.baselineHR, 62, accuracy: 0.001)
    }

    func testTrendIsLastMinusBaseline() {
        let t = BaselineTracker()
        for v in [50.0, 50, 50, 50, 80] { t.update(hr: v, hrv: 40, accel: 0.5) }
        // baseline = (50*4 + 80)/5 = 56; last = 80; trend = 24
        XCTAssertEqual(t.baselineHR, 56, accuracy: 0.001)
        XCTAssertEqual(t.hrTrend, 24, accuracy: 0.001)
    }

    func testNilHRIsSkippedButAccelStillRecorded() {
        let t = BaselineTracker()
        t.update(hr: nil, hrv: nil, accel: 0.5)
        t.update(hr: nil, hrv: nil, accel: 0.7)
        XCTAssertEqual(t.baselineHR, 0)              // no HR ever recorded
        XCTAssertEqual(t.baselineAccel, 0.6, accuracy: 0.001)
        XCTAssertFalse(t.hasEnoughMotionData)         // only 2 readings
    }

    func testHasEnoughDataRequiresThirtyOfEach() {
        let t = BaselineTracker()
        for _ in 0..<29 { t.update(hr: 60, hrv: 40, accel: 0.5) }
        XCTAssertFalse(t.hasEnoughData)
        t.update(hr: 60, hrv: 40, accel: 0.5)        // 30th
        XCTAssertTrue(t.hasEnoughData)
    }

    func testRingBufferOverwritesOldestAndCapsAtCapacity() {
        let t = BaselineTracker()
        // Fill well past capacity with a known final window
        for _ in 0..<400 { t.update(hr: 100, hrv: 50, accel: 1.0) }
        XCTAssertEqual(t.baselineHR, 100, accuracy: 0.001)   // all values identical
        // Now push one different value; baseline should barely move (299 old + 1 new)
        t.update(hr: 40, hrv: 50, accel: 1.0)
        XCTAssertEqual(t.baselineHR, (100 * 299 + 40) / 300, accuracy: 0.001)
    }

    func testResetClearsEverything() {
        let t = BaselineTracker()
        for _ in 0..<50 { t.update(hr: 60, hrv: 40, accel: 0.5) }
        t.reset()
        XCTAssertEqual(t.baselineHR, 0)
        XCTAssertFalse(t.hasEnoughData)
    }
}
