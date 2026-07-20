import Foundation
import SwiftData

/// A manually logged missed attack — an event Wakeme didn't catch.
/// Used to measure recall and to feed the Stage 2 training corpus.
@Model public final class FalseNegativeReport {

    @Attribute(.unique) public var id: UUID
    public var approxTimestamp: Date
    public var notes: String?
    public var linkedWindowRef: String?     // resolved retrospectively to a sensor log window
    public var createdAt: Date

    public init(approxTimestamp: Date, notes: String? = nil) {
        self.id = UUID()
        self.approxTimestamp = approxTimestamp
        self.notes = notes
        self.createdAt = Date()
    }
}
