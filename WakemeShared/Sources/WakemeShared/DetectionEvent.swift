import Foundation

public struct DetectionEvent: Codable, Sendable {
    public var timestamp: Date
    public var triggeringVector: FeatureVector
    public var confidence: Double
    public var mode: SessionMode
    public var activityContext: ActivityContext

    public init(
        timestamp: Date,
        triggeringVector: FeatureVector,
        confidence: Double,
        mode: SessionMode,
        activityContext: ActivityContext
    ) {
        self.timestamp = timestamp
        self.triggeringVector = triggeringVector
        self.confidence = confidence
        self.mode = mode
        self.activityContext = activityContext
    }
}
