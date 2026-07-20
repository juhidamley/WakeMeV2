import Foundation
import SwiftData

@Model public final class ModelVersion {

    @Attribute(.unique) public var id: UUID
    public var version: Int
    public var isPersonalized: Bool
    public var trainedAt: Date?
    public var trainingEventCount: Int
    public var isDeployed: Bool

    public init(version: Int, isPersonalized: Bool = false) {
        self.id = UUID()
        self.version = version
        self.isPersonalized = isPersonalized
        self.trainingEventCount = 0
        self.isDeployed = false
    }
}
