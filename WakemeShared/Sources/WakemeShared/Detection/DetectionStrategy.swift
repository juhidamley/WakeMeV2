import Foundation

public protocol DetectionStrategy: Sendable {
    var version: Int { get }
    func evaluate(_ vector: FeatureVector) -> Double
}
