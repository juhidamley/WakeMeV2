import Foundation
import CoreMotion
import SwiftData
import Observation
import WakemeShared

@Observable
@MainActor
public final class SensorCoordinator {

    public static let shared = SensorCoordinator()

    public private(set) var currentMode: SessionMode = .passive
    public private(set) var currentContext: ActivityContext = .unknown
    public private(set) var currentSession: MonitoringSession?

    @ObservationIgnored private let activityManager = ActivityContextManager()
    @ObservationIgnored private let activeManager = ActiveSessionManager()

    /// The detection engine subscribes here. Called on the main actor.
    @ObservationIgnored
    public var onFeatureVector: (@MainActor (FeatureVector) -> Void)?

    /// Optional hook so the driving interrupt (Step 5.1) can silently log vectors while
    /// automotive, without SensorCoordinator depending on that type. Set by Step 5.1.
    @ObservationIgnored
    public var onSilentDrivingVector: (@MainActor (FeatureVector) -> Void)?

    /// Weak handle to the calibration record so we can seed the motion baseline.
    /// Set once at app launch (Step 7.1 wiring on Watch).
    @ObservationIgnored
    public weak var calibration: CalibrationData?

    @ObservationIgnored private var contextSyncTimer: Timer?
    @ObservationIgnored private var lastStatusSend: Date = .distantPast

    // Passive 1 Hz motion sampler — feeds CalibrationData during stationary wear.
    @ObservationIgnored private let passiveMotionManager = CMMotionManager()

    private init() {}

    // MARK: - Passive monitoring

    public func startPassiveMonitoring() {
        activityManager.start()
        startContextSync()
        startPassiveBaselineSampling()
        currentMode = .passive
        // Wire the active manager's emissions through our router even though it's not started yet,
        // so we don't miss the closure assignment when a session later begins.
        activeManager.onFeatureVector = { [weak self] vector in
            self?.route(vector)
        }
    }

    public func stopAll() async {
        contextSyncTimer?.invalidate()
        contextSyncTimer = nil
        passiveMotionManager.stopDeviceMotionUpdates()
        activityManager.stop()
        if activeManager.isRunning {
            await activeManager.stop()
        }
        currentSession = nil
        currentMode = .passive
    }

    // MARK: - Active session

    public func startActiveSession(
        mode: SessionMode,
        escalationCeiling: EscalationCeiling,
        modelContext: ModelContext
    ) async throws {
        guard currentMode == .passive else { return }

        let session = MonitoringSession(
            startTime: Date(),
            mode: mode,
            escalationCeiling: escalationCeiling
        )
        modelContext.insert(session)
        currentSession = session
        currentMode = mode

        try await activeManager.start(activityContext: currentContext)
    }

    public func stopActiveSession(modelContext: ModelContext) async {
        guard currentMode != .passive else { return }

        await activeManager.stop()
        currentSession?.endTime = Date()
        currentSession = nil
        currentMode = .passive
    }

    // MARK: - Context sync

    private func startContextSync() {
        // @Observable provides no free callback, so we poll once per second.
        // 1 s lag is imperceptible for a mode-switch decision.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ctx = self.activityManager.currentContext
                if ctx != self.currentContext {
                    self.currentContext = ctx
                    DrivingInterruptManager.shared.update(context: ctx)
                }
                self.pushStatusIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contextSyncTimer = timer
    }

    private func pushStatusIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastStatusSend) >= 5 else { return }
        lastStatusSend = now
        WCSessionManager.shared.sendContext([
            "mode": currentMode.rawValue,
            "context": currentContext.rawValue,
            "confidence": DetectionEngine.shared.currentConfidence,
            "isArmed": DetectionEngine.shared.isArmed,
            "hr": WCSessionManager.shared.watchStatus.lastHeartRate as Any
        ])
    }

    // MARK: - Passive motion baseline seeding

    private func startPassiveBaselineSampling() {
        guard passiveMotionManager.isDeviceMotionAvailable else { return }
        passiveMotionManager.deviceMotionUpdateInterval = 1.0  // 1 Hz — minimal battery cost
        let queue = OperationQueue()
        passiveMotionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let m = motion else { return }
            let mag = sqrt(m.userAcceleration.x * m.userAcceleration.x
                         + m.userAcceleration.y * m.userAcceleration.y
                         + m.userAcceleration.z * m.userAcceleration.z)
            Task { @MainActor [weak self] in
                self?.seedMotionBaseline(magnitude: mag)
            }
        }
    }

    /// Rolling mean update: only accumulates samples when context is stationary so walking
    /// or driving don't inflate the resting-motion baseline.
    private func seedMotionBaseline(magnitude: Double) {
        guard currentContext == .stationary, let cal = calibration else { return }
        let n = cal.motionBaselineSamples
        let oldMean = cal.motionBaseline ?? 0.0
        // Welford-style single-pass update: newMean = (oldMean * n + value) / (n + 1)
        cal.motionBaseline = (oldMean * Double(n) + magnitude) / Double(n + 1)
        cal.motionBaselineSamples = n + 1
        cal.lastUpdated = Date()
    }

    // MARK: - Vector routing

    private func route(_ vector: FeatureVector) {
        switch ContextPolicy.response(for: currentContext) {
        case .interrupt:
            // Automotive — silence the alarm, but offer vectors for silent driving-interrupt
            // logging (Step 5.1). If the hook isn't set yet, vectors are silently dropped.
            onSilentDrivingVector?(vector)
        case .monitor, .earlyWarning:
            onFeatureVector?(vector)
        }
        pushStatusIfNeeded()
    }
}
