import Foundation

public enum DismissType: String, Codable, Sendable, CaseIterable {
    case falseAlarm, confirmedAttack, noResponse
}

public enum SessionMode: String, Codable, Sendable, CaseIterable {
    case passive, active
}

public enum ActivityContext: String, Codable, Sendable, CaseIterable {
    case stationary, walking, running, automotive, unknown
}

public enum EscalationCeiling: String, Codable, Sendable, CaseIterable {
    case silent, hapticOnly, hapticThenTone, fullAlarm
}

public enum ContextResponse: Sendable {
    case monitor, interrupt, earlyWarning
}
