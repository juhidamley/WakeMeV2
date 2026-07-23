import Foundation

/// Replays recorded FeatureVectors through the detection confirmation logic and scores the run
/// against known attack markers. Pure logic — runs on the simulator, no hardware.
public final class ReplayHarness {

    public struct ReplayResult: Sendable {
        public var fired: [Date]          // timestamps where a detection would have fired
        public var markers: [Date]        // ground-truth attack timestamps
        public var truePositives: Int     // fires within the match window of a marker
        public var falsePositives: Int    // fires NOT near any marker
        public var precision: Double      // truePositives / total fires
        public var recall: Double         // markers matched by a fire / total markers
    }

    /// Input bundle: the recorded vectors plus the ground-truth marker timestamps.
    public struct ReplayInput: Codable, Sendable {
        public var vectors: [FeatureVector]
        public var markers: [Date]
        public init(vectors: [FeatureVector], markers: [Date]) {
            self.vectors = vectors
            self.markers = markers
        }
    }

    private let bufferSize = 5
    private let requiredConsecutive = 3
    private let matchWindow: TimeInterval = 60   // seconds

    public init() {}

    // MARK: - Run from a decoded input
    public func run(input: ReplayInput, strategy: any DetectionStrategy, threshold: Double) -> ReplayResult {
        var confidenceBuffer: [Double] = []
        var fired: [Date] = []

        for vector in input.vectors {
            let confidence = strategy.evaluate(vector)
            confidenceBuffer.append(confidence)
            if confidenceBuffer.count > bufferSize {
                confidenceBuffer.removeFirst(confidenceBuffer.count - bufferSize)
            }
            let recent = confidenceBuffer.suffix(requiredConsecutive)
            if recent.count >= requiredConsecutive && recent.allSatisfy({ $0 >= threshold }) {
                fired.append(vector.timestamp)
                confidenceBuffer.removeAll()   // mirror DetectionEngine's re-fire reset
            }
        }

        let markers = input.markers

        // A fire is a true positive if it lands within matchWindow of any marker.
        var matchedMarkers = Set<Int>()
        var truePositives = 0
        for f in fired {
            if let idx = markers.firstIndex(where: { abs($0.timeIntervalSince(f)) <= matchWindow }) {
                truePositives += 1
                matchedMarkers.insert(idx)
            }
        }
        let falsePositives = fired.count - truePositives

        return ReplayResult(
            fired: fired,
            markers: markers,
            truePositives: truePositives,
            falsePositives: falsePositives,
            precision: fired.isEmpty ? 0 : Double(truePositives) / Double(fired.count),
            recall: markers.isEmpty ? 0 : Double(matchedMarkers.count) / Double(markers.count)
        )
    }

    // MARK: - Run from a .json file (a ReplayInput encoded as JSON)
    public func run(fileURL: URL, strategy: any DetectionStrategy, threshold: Double) throws -> ReplayResult {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let input = try decoder.decode(ReplayInput.self, from: data)
        return run(input: input, strategy: strategy, threshold: threshold)
    }
}
