import Foundation
import SwiftData
import Observation
import WakemeShared

@Observable
@MainActor
public final class DrivingInterruptManager {

    public static let shared = DrivingInterruptManager()

    public private(set) var isInAutomotiveContext: Bool = false
    public var showsDrivingWarning: Bool = false

    @ObservationIgnored private var hasShownWarningThisDrive: Bool = false
    @ObservationIgnored private var currentDriveID: UUID?

    // Set at launch (Step 7.1). Persisting the drowsiness corpus needs a context; because
    // ModelContext isn't Sendable we hold it as a non-observed reference set on the main actor.
    @ObservationIgnored public var modelContext: ModelContext?

    private init() {}

    /// Call whenever SensorCoordinator.currentContext changes.
    public func update(context: ActivityContext) {
        let nowAutomotive = (context == .automotive)
        guard nowAutomotive != isInAutomotiveContext else { return }
        isInAutomotiveContext = nowAutomotive
        if nowAutomotive { onEnterAutomotive() } else { onExitAutomotive() }
    }

    private func onEnterAutomotive() {
        currentDriveID = UUID()
        hasShownWarningThisDrive = false

        // One-time warning per drive — show it now and mark as shown for this drive.
        if !hasShownWarningThisDrive {
            showsDrivingWarning = true
            hasShownWarningThisDrive = true
        }

        // Cancel any in-flight escalation — we do not alert while driving.
        if case .escalating = AlertManager.shared.alertState {
            AlertManager.shared.dismiss(as: .noResponse, modelContext: modelContext)
        }
    }

    private func onExitAutomotive() {
        showsDrivingWarning = false
        // Reset so the warning appears again on the NEXT drive.
        hasShownWarningThisDrive = false
        currentDriveID = nil
    }

    /// Persist a silently-collected vector while driving. Wired to SensorCoordinator.onSilentDrivingVector.
    public func logSilentVector(_ vector: FeatureVector) {
        guard isInAutomotiveContext, let driveID = currentDriveID, let ctx = modelContext else { return }
        let sample = DrivingDrowsinessSample(from: vector, driveSessionID: driveID)
        ctx.insert(sample)
        // Light-touch save; these are low-frequency (one per ~2s only while driving).
        try? ctx.save()
        // TODO Option C: train a trend-based pre-onset detector on DrivingDrowsinessSample records.
    }
}
