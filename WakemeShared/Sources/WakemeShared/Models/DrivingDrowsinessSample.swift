import Foundation
import SwiftData

/// One silently-logged feature sample captured while driving. This is the seed corpus for the
/// future Option C drowsiness early-warning model. NOT used for any alerting in v1.
@Model public final class DrivingDrowsinessSample {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var heartRate: Double
    public var hrv: Double
    public var meanAccelMagnitude: Double
    public var baselineHR: Double
    public var baselineAccel: Double
    public var hrTrend: Double
    public var hrvTrend: Double
    public var accelTrend: Double
    public var driveSessionID: UUID   // groups samples from one continuous drive

    public init(from vector: FeatureVector, driveSessionID: UUID) {
        self.id = UUID()
        self.timestamp = vector.timestamp
        self.heartRate = vector.heartRate
        self.hrv = vector.hrv
        self.meanAccelMagnitude = vector.meanAccelMagnitude
        self.baselineHR = vector.baselineHR
        self.baselineAccel = vector.baselineAccel
        self.hrTrend = vector.hrTrend
        self.hrvTrend = vector.hrvTrend
        self.accelTrend = vector.accelTrend
        self.driveSessionID = driveSessionID
    }
}
