import Foundation

// MARK: – How a sleep-attack alert was dismissed

public enum DismissType: String, Codable, Sendable {
    case userResponded      // User tapped / interacted deliberately
    case noResponse         // Timer elapsed with no interaction
    case falseAlarm         // User flagged as not a real event
    case autoCleared        // System cleared (e.g. motion resumed)
}

// MARK: – Active monitoring mode for a session

public enum SessionMode: String, Codable, Sendable {
    case passive            // Background low-power monitoring
    case active             // Foreground high-sensitivity monitoring
    case driving            // Elevated sensitivity, driving context
}

// MARK: – What the user was doing when the event was detected

public enum ActivityContext: String, Codable, Sendable {
    case unknown
    case sitting
    case standing
    case walking
    case driving
    case reading
    case watching
    case working
}

// MARK: – Maximum escalation stage allowed in a session

public enum EscalationCeiling: String, Codable, Sendable {
    case hapticOnly         // Stage 1: wrist tap only
    case hapticAndSound     // Stage 2: haptic + audio tone
    case loudAlarm          // Stage 3: loud alarm
    case fullAlarm          // Stage 4: full alarm + phone alert
}
