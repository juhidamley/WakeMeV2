import Foundation
import SwiftData
import Observation
import WakemeShared

@Observable
@MainActor
public final class PersonalizationManager {

    public var isTraining = false
    public var trainingProgress: Double = 0
    public var lastTrainedVersion: Int?
    public var lastTrainingError: String?

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Gate

    /// Whether the training gate is open. Must match InsightsScreen.canTrain exactly:
    /// ≥10 confirmed attacks AND ≥5 false alarms (reclassified events count because they
    /// already carry .confirmedAttack / .falseAlarm after review).
    public var isReadyToTrain: Bool {
        let all = (try? modelContext.fetch(FetchDescriptor<SleepAttackEvent>())) ?? []
        let c = all.filter { $0.dismissType == .confirmedAttack }.count
        let f = all.filter { $0.dismissType == .falseAlarm }.count
        return c >= 10 && f >= 5
    }

    // MARK: - Training

    public func startTraining() async {
        guard !isTraining, isReadyToTrain else { return }
        isTraining = true
        trainingProgress = 0
        lastTrainingError = nil

        // Pull events that have both a label AND sensor data we can train on.
        let (confirmed, falseAlarms) = labeledEventsWithSnapshots()

        func makeSample(_ e: SleepAttackEvent, label: Double) -> LogisticTrainer.Sample? {
            guard let s = e.signalSnapshot else { return nil }
            let f = PersonalizationFeatures.from(
                hr: s.heartRate, hrv: s.hrv, accel: s.wristAccelMagnitude,
                baselineHR: s.baselineHR, baselineHRV: s.baselineHRV, baselineAccel: s.baselineAccel,
                hrTrend: s.hrTrend, hrvTrend: s.hrvTrend, accelTrend: s.accelTrend
            )
            return LogisticTrainer.Sample(features: f.values, label: label)
        }

        let samples = confirmed.compactMap { makeSample($0, label: 1) }
                    + falseAlarms.compactMap { makeSample($0, label: 0) }

        guard samples.count >= 15 else {
            lastTrainingError = "Not enough labeled samples with sensor data (\(samples.count)/15)."
            isTraining = false
            return
        }

        let nextVersion = (currentDeployedVersion() ?? 1) + 1

        // Run training off the main actor so the UI stays responsive.
        let result = await Task.detached(priority: .utility) { [samples] in
            LogisticTrainer.train(samples: samples) { p in
                Task { @MainActor in self.trainingProgress = p }
            }
        }.value

        let weights = LogisticWeights(weights: result.weights, bias: result.bias, version: nextVersion)

        do {
            // Persist weights JSON to Documents/models/personalized_v{n}.json
            let modelsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("models", isDirectory: true)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            let weightsURL = modelsDir.appendingPathComponent("personalized_v\(nextVersion).json")

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(weights).write(to: weightsURL)

            // Update ModelVersion records — flip the deployed flag.
            let versions = (try? modelContext.fetch(FetchDescriptor<ModelVersion>())) ?? []
            versions.forEach { $0.isDeployed = false }
            let mv = ModelVersion(version: nextVersion, isPersonalized: true)
            mv.trainedAt = Date()
            mv.trainingEventCount = samples.count
            mv.isDeployed = true
            modelContext.insert(mv)
            try? modelContext.save()

            // Remember for connectivity handshake.
            UserDefaults.standard.set(nextVersion, forKey: "iosDeployedModelVersion")

            // Deliver to Watch via transferFile (metadata distinguishes from future coreml models).
            WCSessionManager.shared.sendWeights(at: weightsURL, version: nextVersion)

            lastTrainedVersion = nextVersion
        } catch {
            lastTrainingError = error.localizedDescription
        }

        isTraining = false
    }

    // MARK: - Helpers

    private func labeledEventsWithSnapshots()
        -> (confirmed: [SleepAttackEvent], falseAlarms: [SleepAttackEvent])
    {
        let all = (try? modelContext.fetch(FetchDescriptor<SleepAttackEvent>())) ?? []
        let usable = all.filter { $0.dismissType != .noResponse && $0.signalSnapshot != nil }
        return (
            usable.filter { $0.dismissType == .confirmedAttack },
            usable.filter { $0.dismissType == .falseAlarm }
        )
    }

    private func currentDeployedVersion() -> Int? {
        let versions = (try? modelContext.fetch(FetchDescriptor<ModelVersion>())) ?? []
        return versions.first(where: { $0.isDeployed })?.version
    }
}
