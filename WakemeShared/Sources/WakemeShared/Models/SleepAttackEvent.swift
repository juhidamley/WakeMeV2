import Foundation
import SwiftData

@Model public final class SleepAttackEvent {

    @Attribute(.unique) public var id: UUID

    public var timestamp: Date
    public var duration: TimeInterval           // seconds, detection → dismiss
    public var severity: Int                    // 1–4: escalation stage reached before dismiss
    public var confidence: Double               // detector confidence at trigger (0–1)

    // Stored as raw strings so SwiftData can persist them without Codable boxing issues
    public var dismissTypeRaw: String
    public var monitoringModeRaw: String
    public var activityContextRaw: String

    public var wasReclassified: Bool
    public var originalDismissTypeRaw: String?  // set when wasReclassified == true
    public var rawWindowRef: String?            // file reference for confirmed-event raw window
    public var modelVersion: Int

    // Relationships
    @Relationship(deleteRule: .cascade)
    public var signalSnapshot: SignalSnapshot?

    @Relationship(inverse: \MonitoringSession.events)
    public var session: MonitoringSession?

    public init(
        timestamp: Date,
        duration: TimeInterval,
        severity: Int,
        confidence: Double,
        dismissType: DismissType,
        monitoringMode: SessionMode,
        activityContext: ActivityContext,
        modelVersion: Int
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.duration = duration
        self.severity = severity
        self.confidence = confidence
        self.dismissTypeRaw = dismissType.rawValue
        self.monitoringModeRaw = monitoringMode.rawValue
        self.activityContextRaw = activityContext.rawValue
        self.wasReclassified = false
        self.modelVersion = modelVersion
    }

    // MARK: – Typed accessors
    public var dismissType: DismissType {
        get { DismissType(rawValue: dismissTypeRaw) ?? .noResponse }
        set { dismissTypeRaw = newValue.rawValue }
    }
    public var monitoringMode: SessionMode {
        get { SessionMode(rawValue: monitoringModeRaw) ?? .passive }
        set { monitoringModeRaw = newValue.rawValue }
    }
    public var activityContext: ActivityContext {
        get { ActivityContext(rawValue: activityContextRaw) ?? .unknown }
        set { activityContextRaw = newValue.rawValue }
    }
    public var originalDismissType: DismissType? {
        get { originalDismissTypeRaw.flatMap { DismissType(rawValue: $0) } }
        set { originalDismissTypeRaw = newValue?.rawValue }
    }
}
