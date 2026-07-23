import Foundation

/// A primitives-only, Codable mirror of SleepAttackEvent for cross-device transfer.
/// Never send SwiftData @Model types over WatchConnectivity.
public struct SleepAttackEventTransfer: Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var duration: TimeInterval
    public var severity: Int
    public var confidence: Double
    public var dismissTypeRaw: String
    public var monitoringModeRaw: String
    public var activityContextRaw: String
    public var modelVersion: Int

    public init(from event: SleepAttackEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.duration = event.duration
        self.severity = event.severity
        self.confidence = event.confidence
        self.dismissTypeRaw = event.dismissType.rawValue
        self.monitoringModeRaw = event.monitoringMode.rawValue
        self.activityContextRaw = event.activityContext.rawValue
        self.modelVersion = event.modelVersion
    }

    /// Reconstruct a SleepAttackEvent (without signalSnapshot/session — those stay Watch-side).
    @MainActor public func toSleepAttackEvent() -> SleepAttackEvent {
        SleepAttackEvent(
            timestamp: timestamp,
            duration: duration,
            severity: severity,
            confidence: confidence,
            dismissType: DismissType(rawValue: dismissTypeRaw) ?? .noResponse,
            monitoringMode: SessionMode(rawValue: monitoringModeRaw) ?? .passive,
            activityContext: ActivityContext(rawValue: activityContextRaw) ?? .unknown,
            modelVersion: modelVersion
        ).withID(id)
    }
}

// Helper so the reconstructed event keeps the original id (for dedup).
private extension SleepAttackEvent {
    @MainActor func withID(_ id: UUID) -> SleepAttackEvent {
        self.id = id
        return self
    }
}
