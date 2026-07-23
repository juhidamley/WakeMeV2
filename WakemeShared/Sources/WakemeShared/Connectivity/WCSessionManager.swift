import Foundation
import WatchConnectivity
import Observation
#if canImport(SwiftData)
import SwiftData
#endif

@Observable
public final class WCSessionManager: NSObject, WCSessionDelegate {

    public static let shared = WCSessionManager()

    // MARK: - Observed state (always mutated on the main actor)
    public var isReachable: Bool = false
    public var pendingTransferCount: Int = 0
    public var lastSyncDate: Date?
    public var watchStatus: WatchStatus = WatchStatus()

    // Set by the iOS app entry point so received events can be persisted.
    @ObservationIgnored
    public var modelContext: ModelContext?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Watch→iPhone: reliable event delivery

    /// Encode and queue one event for delivery. Uses transferUserInfo (FIFO, survives lock/bag).
    /// Call only from the Watch side.
    public func syncEvent(_ event: SleepAttackEvent) {
        #if os(watchOS)
        guard WCSession.isSupported() else { return }
        guard let data = try? JSONEncoder.wakeme.encode(SleepAttackEventTransfer(from: event)) else { return }
        WCSession.default.transferUserInfo(["event": data])
        let count = WCSession.default.outstandingUserInfoTransfers.count
        Task { @MainActor in self.pendingTransferCount = count }
        #endif
    }

    // MARK: - Watch→iPhone: live status (latest-value-wins)

    /// Push latest Watch state to the paired iPhone. Uses updateApplicationContext so only
    /// the most recent snapshot is kept; older snapshots are discarded by the system.
    /// Call only from the Watch side; values must be property-list compatible.
    public func sendContext(_ context: [String: Any]) {
        #if os(watchOS)
        guard WCSession.isSupported() else { return }
        // Strip Optional.none values — they are not property-list compatible.
        var safe: [String: Any] = [:]
        for (key, value) in context {
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .optional, mirror.children.isEmpty { continue }
            safe[key] = value
        }
        try? WCSession.default.updateApplicationContext(safe)
        #endif
    }

    // MARK: - iPhone→Watch: model delivery (future step)

    public func sendModel(at url: URL, version: Int) {
        // Phase 7 — transferFile with metadata (CoreML model)
    }

    // MARK: - iPhone→Watch: personalized logistic weights

    /// Delivers a JSON weights file to the Watch via transferFile.
    /// The "personalizedWeights" type metadata lets the Watch distinguish this from a future
    /// CoreML model transfer that will use the same transferFile path.
    public func sendWeights(at url: URL, version: Int) {
        #if os(iOS)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferFile(url, metadata: ["type": "personalizedWeights", "modelVersion": version])
        let count = WCSession.default.outstandingFileTransfers.count
        Task { @MainActor in self.pendingTransferCount = count }
        #endif
    }

    // MARK: - iPhone→Watch: settings (future step)

    public func sendSettings(passiveThreshold: Double, activeThreshold: Double) {
        // Phase 7 — updateApplicationContext
    }

    // MARK: - WCSessionDelegate (required)
    // Delegate callbacks arrive on a background queue. Always hop to the main actor before
    // touching any @Observable property to avoid data races.

    public func session(_ session: WCSession,
                        activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        // iOS requires reactivation after Watch pairing changes.
        session.activate()
    }
    #endif

    // MARK: - Receive: events (iOS side)

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        #if os(iOS)
        guard let data = userInfo["event"] as? Data,
              let transfer = try? JSONDecoder.wakeme.decode(SleepAttackEventTransfer.self, from: data)
        else { return }

        // Capture id as a local let — #Predicate cannot traverse struct property chains.
        let incomingID = transfer.id
        Task { @MainActor in
            guard let ctx = self.modelContext else { return }
            let descriptor = FetchDescriptor<SleepAttackEvent>(
                predicate: #Predicate { $0.id == incomingID }
            )
            let existing = (try? ctx.fetch(descriptor)) ?? []
            guard existing.isEmpty else { return }   // already received, skip
            let event = transfer.toSleepAttackEvent()
            ctx.insert(event)
            self.lastSyncDate = Date()
            self.pendingTransferCount = max(0, self.pendingTransferCount - 1)
        }
        #endif
    }

    // MARK: - Receive: live Watch status (iOS side)

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(iOS)
        let modeRaw    = applicationContext["mode"]       as? String ?? SessionMode.passive.rawValue
        let ctxRaw     = applicationContext["context"]    as? String ?? ActivityContext.unknown.rawValue
        let confidence = applicationContext["confidence"] as? Double ?? 0
        let isArmed    = applicationContext["isArmed"]    as? Bool   ?? false
        let hr         = applicationContext["hr"]         as? Double

        Task { @MainActor in
            self.watchStatus = WatchStatus(
                mode:            SessionMode(rawValue: modeRaw)        ?? .passive,
                activityContext: ActivityContext(rawValue: ctxRaw)     ?? .unknown,
                confidence:      confidence,
                isArmed:         isArmed,
                lastHeartRate:   hr
            )
        }
        #endif
    }

    // MARK: - Receive: files

    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(watchOS)
        if file.metadata?["type"] as? String == "personalizedWeights",
           let version = file.metadata?["modelVersion"] as? Int {
            let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("models/weights_v\(version).json")
            let dir = dest.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: file.fileURL, to: dest)
            Task { @MainActor in ModelManager.shared.installWeights(at: dest, version: version) }
            return
        }
        // coremlModel branch retained for future use.
        #endif
    }
}

// MARK: - WatchStatus

public struct WatchStatus: Sendable {
    public var mode: SessionMode
    public var activityContext: ActivityContext
    public var confidence: Double
    public var isArmed: Bool
    public var lastHeartRate: Double?

    public init(
        mode: SessionMode = .passive,
        activityContext: ActivityContext = .unknown,
        confidence: Double = 0,
        isArmed: Bool = false,
        lastHeartRate: Double? = nil
    ) {
        self.mode = mode
        self.activityContext = activityContext
        self.confidence = confidence
        self.isArmed = isArmed
        self.lastHeartRate = lastHeartRate
    }
}

// MARK: - Shared coders

public extension JSONEncoder {
    static let wakeme: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

public extension JSONDecoder {
    static let wakeme: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
