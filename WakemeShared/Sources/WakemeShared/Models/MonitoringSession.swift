import Foundation
import SwiftData

@Model public final class MonitoringSession {

    @Attribute(.unique) public var id: UUID
    public var startTime: Date
    public var endTime: Date?
    public var modeRaw: String
    public var escalationCeilingRaw: String

    @Relationship(deleteRule: .cascade)
    public var events: [SleepAttackEvent]

    public init(startTime: Date, mode: SessionMode, escalationCeiling: EscalationCeiling) {
        self.id = UUID()
        self.startTime = startTime
        self.modeRaw = mode.rawValue
        self.escalationCeilingRaw = escalationCeiling.rawValue
        self.events = []
    }

    public var mode: SessionMode {
        get { SessionMode(rawValue: modeRaw) ?? .passive }
        set { modeRaw = newValue.rawValue }
    }
    public var escalationCeiling: EscalationCeiling {
        get { EscalationCeiling(rawValue: escalationCeilingRaw) ?? .fullAlarm }
        set { escalationCeilingRaw = newValue.rawValue }
    }
    public var eventsDetected: Int { events.count }
}
