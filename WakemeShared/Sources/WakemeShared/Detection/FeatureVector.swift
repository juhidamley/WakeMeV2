import Foundation

public struct FeatureVector: Codable, Sendable {
    public var timestamp: Date
    public var heartRate: Double
    public var hrv: Double
    public var meanAccelMagnitude: Double
    public var peakAccelMagnitude: Double
    public var gyroMagnitude: Double
    public var baselineHR: Double
    public var baselineHRV: Double
    public var baselineAccel: Double
    public var hrTrend: Double
    public var hrvTrend: Double
    public var accelTrend: Double
    public var activityContext: ActivityContext

    // Explicit public init — the synthesized memberwise init is internal and
    // would be invisible to the app targets.
    public init(
        timestamp: Date,
        heartRate: Double,
        hrv: Double,
        meanAccelMagnitude: Double,
        peakAccelMagnitude: Double,
        gyroMagnitude: Double,
        baselineHR: Double,
        baselineHRV: Double,
        baselineAccel: Double,
        hrTrend: Double,
        hrvTrend: Double,
        accelTrend: Double,
        activityContext: ActivityContext
    ) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.hrv = hrv
        self.meanAccelMagnitude = meanAccelMagnitude
        self.peakAccelMagnitude = peakAccelMagnitude
        self.gyroMagnitude = gyroMagnitude
        self.baselineHR = baselineHR
        self.baselineHRV = baselineHRV
        self.baselineAccel = baselineAccel
        self.hrTrend = hrTrend
        self.hrvTrend = hrvTrend
        self.accelTrend = accelTrend
        self.activityContext = activityContext
    }
}
