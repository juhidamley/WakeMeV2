import Foundation
import Observation
import WakemeShared

/// Manages the active detection model on the Watch. Persists the deployed weights path so
/// the model survives app restarts, and hot-swaps TrainedStrategy into DetectionEngine.
@Observable
@MainActor
public final class ModelManager {

    public static let shared = ModelManager()

    public private(set) var currentVersion: Int?

    private init() {}

    // MARK: - Install from file

    public func installWeights(at url: URL, version: Int) {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let weights = try? decoder.decode(LogisticWeights.self, from: data) else { return }

        currentVersion = version
        UserDefaults.standard.set(version, forKey: "deployedModelVersion")
        UserDefaults.standard.set(url.path, forKey: "deployedWeightsPath")

        DetectionEngine.shared.install(strategy: TrainedStrategy(model: weights))
    }

    // MARK: - Restore on launch

    /// Call once in bootstrap after the heuristic strategy is installed.
    /// If a previously delivered weights file exists, it hot-swaps over the heuristic.
    public func loadSavedWeightsIfAvailable() {
        guard
            let path    = UserDefaults.standard.string(forKey: "deployedWeightsPath"),
            let version = UserDefaults.standard.object(forKey: "deployedModelVersion") as? Int,
            FileManager.default.fileExists(atPath: path)
        else { return }
        installWeights(at: URL(fileURLWithPath: path), version: version)
    }
}
