import Foundation

public struct ContextPolicy {
    public static func response(for context: ActivityContext) -> ContextResponse {
        switch context {
        case .automotive:
            return .interrupt          // Option A: step back while driving
        case .stationary, .walking, .running, .unknown:
            return .monitor
        }
        // NOTE: .earlyWarning is intentionally unused in v1 — it's the seam where the
        // future drowsiness early-warning track (Option C) plugs in for .automotive.
    }
}
