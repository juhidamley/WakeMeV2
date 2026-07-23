import Foundation
import Observation
import WakemeShared

@Observable
@MainActor
public final class DetectionEngine {

    public static let shared = DetectionEngine()

    public private(set) var currentConfidence: Double = 0
    public private(set) var isArmed: Bool = false        // 2 of last `requiredConsecutive` over threshold

    /// Fired when a detection is confirmed. Assigned by AlertManager (Step 4.1).
    @ObservationIgnored
    public var onDetectionEvent: (@MainActor (DetectionEvent) -> Void)?

    // No default strategy — must be installed once CalibrationData is available.
    @ObservationIgnored
    private var strategy: (any DetectionStrategy)?

    @ObservationIgnored private var confidenceBuffer: [Double] = []
    @ObservationIgnored private let bufferSize = 5
    @ObservationIgnored private let requiredConsecutive = 3

    private var passiveThreshold: Double {
        UserDefaults.standard.object(forKey: "thresholdPassive") as? Double ?? 0.72
    }
    private var activeThreshold: Double {
        UserDefaults.standard.object(forKey: "thresholdActive") as? Double ?? 0.60
    }

    private init() {}

    /// Install (or swap) the detection strategy. Call once CalibrationData exists, e.g.
    ///   DetectionEngine.shared.install(strategy: HeuristicStrategy(calibration: cal))
    /// Also used in Phase 9 to hot-swap in a personalized TrainedStrategy.
    public func install(strategy: any DetectionStrategy) {
        self.strategy = strategy
        resetBuffer()
    }

    public var hasStrategy: Bool { strategy != nil }

    public func process(_ vector: FeatureVector, mode: SessionMode) {
        // No strategy yet → nothing to do (still early at launch before calibration).
        guard let strategy else {
            currentConfidence = 0
            return
        }

        // Respect context policy — skip inference while driving (or other non-monitor contexts).
        guard ContextPolicy.response(for: vector.activityContext) == .monitor else {
            currentConfidence = 0
            isArmed = false
            confidenceBuffer.removeAll()
            return
        }

        let confidence = strategy.evaluate(vector)
        currentConfidence = confidence

        confidenceBuffer.append(confidence)
        if confidenceBuffer.count > bufferSize {
            confidenceBuffer.removeFirst(confidenceBuffer.count - bufferSize)
        }

        let threshold = (mode == .active) ? activeThreshold : passiveThreshold

        // "Armed" = warming up: at least 2 of the last `requiredConsecutive` are over threshold.
        let recent = confidenceBuffer.suffix(requiredConsecutive)
        isArmed = recent.filter { $0 >= threshold }.count >= 2

        // Fire only when we actually have `requiredConsecutive` samples AND all of them clear.
        // The `recent.count >= requiredConsecutive` guard prevents allSatisfy returning true on a
        // short or empty collection, which would cause a premature fire.
        if recent.count >= requiredConsecutive && recent.allSatisfy({ $0 >= threshold }) {
            let event = DetectionEvent(
                timestamp: Date(),
                triggeringVector: vector,
                confidence: confidence,
                mode: mode,
                activityContext: vector.activityContext
            )
            confidenceBuffer.removeAll()   // prevent immediate re-fire
            isArmed = false
            onDetectionEvent?(event)
        }
    }

    public func resetBuffer() {
        confidenceBuffer.removeAll()
        currentConfidence = 0
        isArmed = false
    }
}
