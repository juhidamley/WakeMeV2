import Foundation

/// Fixed-order standardized feature vector for personalization training and inference.
/// All values are normalized relative to personal baselines so no single large-magnitude
/// feature dominates the logistic fit.
///
/// Index mapping:
///   0: HR relative drop     (baselineHR - hr) / baselineHR
///   1: HRV relative rise    (hrv - baselineHRV) / baselineHRV
///   2: Accel relative drop  (baselineAccel - accel) / baselineAccel
///   3: HR trend normalized  hrTrend / max(baselineHR, 1)
///   4: HRV trend normalized hrvTrend / max(baselineHRV, 1)
///   5: Accel trend normalized accelTrend / max(baselineAccel, 0.001)
public struct PersonalizationFeatures: Sendable {
    public static let dimension = 6
    public var values: [Double]

    public init(values: [Double]) { self.values = values }

    public static func from(
        hr: Double, hrv: Double, accel: Double,
        baselineHR: Double, baselineHRV: Double, baselineAccel: Double,
        hrTrend: Double, hrvTrend: Double, accelTrend: Double
    ) -> PersonalizationFeatures {
        let bHR  = max(baselineHR,  1)
        let bHRV = max(baselineHRV, 1)
        let bAcc = max(baselineAccel, 0.001)
        return PersonalizationFeatures(values: [
            (bHR  - hr)  / bHR,
            (hrv  - bHRV) / bHRV,
            (bAcc - accel) / bAcc,
            hrTrend  / bHR,
            hrvTrend / bHRV,
            accelTrend / bAcc
        ])
    }

    public static func from(_ v: FeatureVector) -> PersonalizationFeatures {
        from(
            hr: v.heartRate, hrv: v.hrv, accel: v.meanAccelMagnitude,
            baselineHR: v.baselineHR, baselineHRV: v.baselineHRV, baselineAccel: v.baselineAccel,
            hrTrend: v.hrTrend, hrvTrend: v.hrvTrend, accelTrend: v.accelTrend
        )
    }
}

// MARK: - Logistic weights

/// Trained logistic-regression weights. Codable so it can be delivered to the Watch as a tiny JSON file.
public struct LogisticWeights: Codable, Sendable {
    public var weights: [Double]   // length == PersonalizationFeatures.dimension
    public var bias: Double
    public var version: Int
    public var trainedAt: Date

    public init(weights: [Double], bias: Double, version: Int, trainedAt: Date = Date()) {
        self.weights = weights
        self.bias = bias
        self.version = version
        self.trainedAt = trainedAt
    }

    /// Logistic probability that the given features represent a sleep-attack moment.
    public func probability(_ f: PersonalizationFeatures) -> Double {
        guard f.values.count == weights.count else { return 0 }
        var z = bias
        for i in 0..<weights.count { z += weights[i] * f.values[i] }
        return 1.0 / (1.0 + exp(-z))
    }
}

// MARK: - TrainedStrategy

/// A DetectionStrategy backed by trained logistic weights. Drops into DetectionEngine unchanged —
/// same protocol, same threshold, same confirmation buffer.
public final class TrainedStrategy: DetectionStrategy, @unchecked Sendable {
    public let version: Int
    private let model: LogisticWeights

    public init(model: LogisticWeights) {
        self.model = model
        self.version = model.version
    }

    public func evaluate(_ vector: FeatureVector) -> Double {
        model.probability(PersonalizationFeatures.from(vector))
    }
}

// MARK: - LogisticTrainer

/// Pure-Swift batch gradient descent with L2 regularization. No framework dependencies.
/// Intended to run on a background Task.detached to avoid blocking the main actor.
public enum LogisticTrainer {

    public struct Sample: Sendable {
        public let features: [Double]
        public let label: Double    // 1 = confirmed attack, 0 = false alarm / normal

        public init(features: [Double], label: Double) {
            self.features = features
            self.label = label
        }
    }

    public static func train(
        samples: [Sample],
        dimension: Int = PersonalizationFeatures.dimension,
        epochs: Int = 500,
        learningRate: Double = 0.1,
        l2: Double = 0.01,
        progress: ((Double) -> Void)? = nil
    ) -> (weights: [Double], bias: Double) {
        var w = [Double](repeating: 0, count: dimension)
        var b = 0.0
        let n = Double(samples.count)
        guard n > 0 else { return (w, b) }

        for epoch in 0..<epochs {
            var gradW = [Double](repeating: 0, count: dimension)
            var gradB = 0.0
            for s in samples {
                var z = b
                for i in 0..<dimension { z += w[i] * s.features[i] }
                let pred  = 1.0 / (1.0 + exp(-z))
                let error = pred - s.label
                for i in 0..<dimension { gradW[i] += error * s.features[i] }
                gradB += error
            }
            for i in 0..<dimension {
                w[i] -= learningRate * (gradW[i] / n + l2 * w[i])
            }
            b -= learningRate * (gradB / n)
            if epoch % 50 == 0 { progress?(Double(epoch) / Double(epochs)) }
        }
        progress?(1.0)
        return (w, b)
    }
}
