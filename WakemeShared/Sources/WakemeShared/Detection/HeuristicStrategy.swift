import Foundation

public final class HeuristicStrategy: DetectionStrategy, @unchecked Sendable {

    public let version = 1

    private let calibration: CalibrationData

    public init(calibration: CalibrationData) {
        self.calibration = calibration
    }

    // Sensitivity slider (1–5) → threshold multiplier.
    // Level 1 (fewer alerts) → 1.5x thresholds; level 3 → 1.0x; level 5 → 0.5x.
    private var sensitivityMultiplier: Double {
        let stored = UserDefaults.standard.object(forKey: "sensitivityLevel") as? Double
        let level = (stored ?? 3).clamped(to: 1...5)
        return 1.5 - ((level - 1) / 4.0)
    }

    public func evaluate(_ vector: FeatureVector) -> Double {
        guard let rhr = calibration.effectiveRHR,
              let motionBase = calibration.effectiveMotion,
              rhr > 0, motionBase > 0 else {
            return 0.0
        }

        let s = sensitivityMultiplier
        var score = 0.0

        // ── Motion signal (weighted highest) ──
        let motionDrop = (motionBase - vector.meanAccelMagnitude) / motionBase
        let motionThreshold = 0.25 * s
        if motionDrop > motionThreshold * 1.5 {
            score += 0.45
        } else if motionDrop > motionThreshold {
            score += 0.25
        }

        // ── Heart-rate signal ── (falling toward/below personal resting HR)
        let hrDropPercent = (rhr - vector.heartRate) / rhr
        let hrThreshold = 0.05 * s
        if hrDropPercent > hrThreshold * 1.5 {
            score += 0.30
        } else if hrDropPercent > hrThreshold {
            score += 0.15
        }

        // ── HRV signal ── (rising vs personal baseline)
        if let baseHRV = calibration.effectiveHRV, baseHRV > 0 {
            let hrvRisePercent = (vector.hrv - baseHRV) / baseHRV
            let hrvThreshold = 0.10 * s
            if hrvRisePercent > hrvThreshold * 1.5 {
                score += 0.25
            } else if hrvRisePercent > hrvThreshold {
                score += 0.12
            }
        }

        // ── Sleep-HR proximity ── (only if sleepHR exists and is below RHR)
        if let sleepHR = calibration.sleepHR, sleepHR > 0, rhr > sleepHR {
            let sleepProximity = 1.0 - ((vector.heartRate - sleepHR) / (rhr - sleepHR))
            if sleepProximity > 0.8 {
                score += 0.15
            }
        }

        return min(score, 1.0)
    }
}

// Delete this extension if `clamped(to:)` already exists elsewhere in the package.
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/*
 CALIBRATION NOTE
 Signal directions are physiologically-motivated priors, not fitted values. Once real attack
 data accrues, run the ReplayHarness (Step 3.3) to confirm each direction holds and adjust
 thresholds. Sensitivity is tunable from Settings via "sensitivityLevel" with no rebuild.
*/
