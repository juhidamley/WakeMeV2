import Foundation
import SwiftData

@Model public final class SignalSnapshot {

    @Attribute(.unique) public var id: UUID

    // Instantaneous readings at detection time
    public var heartRate: Double
    public var hrv: Double                  // SDNN ms approximation over window
    public var wristAccelMagnitude: Double  // Mean accel magnitude over 10 s window
    public var gyroMagnitude: Double        // Mean gyro magnitude over 10 s window

    // Personal baseline values captured at the same moment (from BaselineTracker)
    public var baselineHR: Double
    public var baselineHRV: Double
    public var baselineAccel: Double

    // Trend = current minus baseline (positive = above baseline)
    public var hrTrend: Double
    public var hrvTrend: Double
    public var accelTrend: Double

    // Detection window
    public var windowStart: Date
    public var windowEnd: Date

    public init(
        heartRate: Double,
        hrv: Double,
        wristAccelMagnitude: Double,
        gyroMagnitude: Double,
        baselineHR: Double,
        baselineHRV: Double,
        baselineAccel: Double,
        hrTrend: Double,
        hrvTrend: Double,
        accelTrend: Double,
        windowStart: Date,
        windowEnd: Date
    ) {
        self.id = UUID()
        self.heartRate = heartRate
        self.hrv = hrv
        self.wristAccelMagnitude = wristAccelMagnitude
        self.gyroMagnitude = gyroMagnitude
        self.baselineHR = baselineHR
        self.baselineHRV = baselineHRV
        self.baselineAccel = baselineAccel
        self.hrTrend = hrTrend
        self.hrvTrend = hrvTrend
        self.accelTrend = accelTrend
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}
