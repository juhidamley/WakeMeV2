import Foundation
import SwiftData
import Observation
import AVFoundation
import WakemeShared
#if os(watchOS)
import WatchKit
#endif

public enum AlertState: Equatable {
    case idle
    case escalating(stage: Int, startedAt: Date)
    case dismissed(type: DismissType, at: Date)
}

// Injectable haptic/alarm layer so the state machine is testable off-device.
public protocol AlertOutput: Sendable {
    @MainActor func haptic(stage: Int)
    @MainActor func alarm(subtle: Bool)
    @MainActor func confirmation()
}

public struct WatchAlertOutput: AlertOutput {
    public init() {}
    // Static so it outlives individual method calls and the player doesn't get released mid-play.
    @ObservationIgnored private static var player: AVAudioPlayer?

    @MainActor public func haptic(stage: Int) {
        #if os(watchOS)
        switch stage {
        case 1: WKInterfaceDevice.current().play(.notification)
        case 2: for _ in 0..<3 { WKInterfaceDevice.current().play(.directionUp) }
        case 3: for _ in 0..<5 { WKInterfaceDevice.current().play(.retry) }
        default: break
        }
        #endif
    }

    @MainActor public func alarm(subtle: Bool) {
        #if os(watchOS)
        if subtle {
            WKInterfaceDevice.current().play(.failure)
        } else {
            guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
                // Fallback: repeated strong haptics if the asset is missing.
                for _ in 0..<8 { WKInterfaceDevice.current().play(.failure) }
                return
            }
            Self.player = try? AVAudioPlayer(contentsOf: url)
            Self.player?.volume = 1.0
            Self.player?.play()
        }
        #endif
    }

    @MainActor public func confirmation() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

@Observable
@MainActor
public final class AlertManager {

    public static let shared = AlertManager(output: WatchAlertOutput())

    public private(set) var alertState: AlertState = .idle
    public private(set) var lastEvent: SleepAttackEvent?

    @ObservationIgnored private let output: AlertOutput
    @ObservationIgnored private var escalationTask: Task<Void, Never>?
    @ObservationIgnored private var detectionStart: Date?
    @ObservationIgnored private var triggeringVector: FeatureVector?
    @ObservationIgnored private var triggeringConfidence: Double = 0
    @ObservationIgnored private var currentCeiling: EscalationCeiling = .fullAlarm

    // Timings exposed so tests can shorten them without rebuilding.
    @ObservationIgnored var stageInterval: Duration = .seconds(15)
    @ObservationIgnored var noResponseGrace: Duration = .seconds(10)

    public init(output: AlertOutput) {
        self.output = output
    }

    /// Call once at Watch launch, after DetectionEngine.shared.install(strategy:), to subscribe to detections.
    public func connectToDetectionEngine() {
        DetectionEngine.shared.onDetectionEvent = { [weak self] event in
            self?.handleDetection(event)
        }
    }

    // MARK: - Detection intake

    /// Public entry point used by DetectionEngine.
    func handleDetection(_ event: DetectionEvent) {
        let ceiling = SensorCoordinator.shared.currentSession?.escalationCeiling ?? .fullAlarm
        handleDetection(event, ceiling: ceiling)
    }

    /// Test seam: allows injecting a specific ceiling without going through SensorCoordinator.
    func handleDetection(_ event: DetectionEvent, ceiling: EscalationCeiling) {
        // Debounce: ignore new detections while already alerting.
        guard case .idle = alertState else { return }
        // Respect driving/other non-monitor contexts.
        guard ContextPolicy.response(for: event.activityContext) == .monitor else { return }

        detectionStart = event.timestamp
        triggeringVector = event.triggeringVector
        triggeringConfidence = event.confidence          // REAL confidence, not a trend value
        currentCeiling = ceiling

        alertState = .escalating(stage: 1, startedAt: Date())
        startEscalation()
    }

    // MARK: - Escalation

    private func startEscalation() {
        escalationTask?.cancel()
        escalationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            self.output.haptic(stage: 1)

            // Stage 2
            try? await Task.sleep(for: self.stageInterval)
            guard !Task.isCancelled, self.isEscalating else { return }
            if self.canEscalateTo(2) {
                self.alertState = .escalating(stage: 2, startedAt: Date())
                self.output.haptic(stage: 2)
            }

            // Stage 3
            try? await Task.sleep(for: self.stageInterval)
            guard !Task.isCancelled, self.isEscalating else { return }
            if self.canEscalateTo(3) {
                self.alertState = .escalating(stage: 3, startedAt: Date())
                self.output.haptic(stage: 3)
            }

            // Stage 4 (audible)
            try? await Task.sleep(for: self.stageInterval)
            guard !Task.isCancelled, self.isEscalating else { return }
            if self.canEscalateTo(4) {
                self.alertState = .escalating(stage: 4, startedAt: Date())
                self.output.alarm(subtle: self.currentCeiling == .hapticThenTone)
            }

            // No-response timeout → auto-dismiss
            try? await Task.sleep(for: self.noResponseGrace)
            guard !Task.isCancelled, self.isEscalating else { return }
            self.dismiss(as: .noResponse)
        }
    }

    private var isEscalating: Bool {
        if case .escalating = alertState { return true }
        return false
    }

    // Ceiling clamp. Stage 4 = audible.
    // .hapticThenTone allows a subtle stage-4 tone; .fullAlarm plays the full alarm.
    private func canEscalateTo(_ stage: Int) -> Bool {
        switch currentCeiling {
        case .silent:         return false        // no escalation beyond the initial state
        case .hapticOnly:     return stage <= 3   // haptics only, never audible
        case .hapticThenTone: return true         // stage 4 allowed but subtle tone
        case .fullAlarm:      return true         // stage 4 full alarm
        }
    }

    // MARK: - Dismiss

    public func dismiss(as type: DismissType, modelContext: ModelContext? = nil) {
        // Capture stage BEFORE changing state so the saved record reflects what the user saw.
        let severity = currentStage
        escalationTask?.cancel()
        escalationTask = nil

        output.confirmation()
        alertState = .dismissed(type: type, at: Date())

        if let ctx = modelContext {
            saveEvent(type: type, severity: severity, context: ctx)
        }

        // Auto-return to idle after the dismissed banner has had time to be seen.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if case .dismissed = self?.alertState {
                self?.alertState = .idle
            }
        }
    }

    private var currentStage: Int {
        if case .escalating(let stage, _) = alertState { return stage }
        return 1
    }

    // MARK: - Persistence

    private func saveEvent(type: DismissType, severity: Int, context: ModelContext) {
        guard let vector = triggeringVector else { return }
        let now = Date()
        let start = detectionStart ?? now

        let snapshot = SignalSnapshot(
            heartRate: vector.heartRate,
            hrv: vector.hrv,
            wristAccelMagnitude: vector.meanAccelMagnitude,
            gyroMagnitude: vector.gyroMagnitude,
            baselineHR: vector.baselineHR,
            baselineHRV: vector.baselineHRV,
            baselineAccel: vector.baselineAccel,
            hrTrend: vector.hrTrend,
            hrvTrend: vector.hrvTrend,
            accelTrend: vector.accelTrend,
            windowStart: start,
            windowEnd: now
        )

        let event = SleepAttackEvent(
            timestamp: start,
            duration: now.timeIntervalSince(start),
            severity: severity,
            confidence: triggeringConfidence,
            dismissType: type,
            monitoringMode: SensorCoordinator.shared.currentMode,
            activityContext: vector.activityContext,
            modelVersion: 1
        )
        event.signalSnapshot = snapshot
        event.session = SensorCoordinator.shared.currentSession

        context.insert(event)
        try? context.save()
        lastEvent = event

        WCSessionManager.shared.syncEvent(event)
    }
}
