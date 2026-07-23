import Foundation
import CoreMotion
import Observation
import WakemeShared

@Observable
@MainActor
public final class ActivityContextManager {

    public private(set) var currentContext: ActivityContext = .unknown
    public private(set) var isAvailable: Bool = CMMotionActivityManager.isActivityAvailable()

    @ObservationIgnored
    private let motionActivityManager = CMMotionActivityManager()

    public init() {}

    public func start() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            isAvailable = false
            return
        }
        // Updates are delivered on the provided queue. Use a background queue and hop to the
        // main actor before mutating observed state, rather than assuming .main delivery.
        let queue = OperationQueue()
        motionActivityManager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let activity else { return }
            let mapped = Self.map(activity)
            Task { @MainActor in
                self?.currentContext = mapped
            }
        }
    }

    public func stop() {
        motionActivityManager.stopActivityUpdates()
        currentContext = .unknown
    }

    // Map CoreMotion's activity to our enum.
    // CMMotionActivity can have multiple flags or none. Prioritize the most safety-relevant
    // (automotive) first. If the classifier is uncertain or nothing is set, return .unknown
    // rather than guessing — ContextPolicy treats .unknown as "monitor", which is the safe default.
    private static func map(_ a: CMMotionActivity) -> ActivityContext {
        if a.automotive { return .automotive }
        if a.running    { return .running }
        if a.walking    { return .walking }
        if a.stationary { return .stationary }
        // a.unknown == true, or no flags set, or low confidence with nothing asserted
        return .unknown
    }
}
