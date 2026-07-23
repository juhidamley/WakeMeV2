import SwiftUI
import SwiftData
import WakemeShared

@main
struct WakeMeWatch_Watch_AppApp: App {

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.makeWakemeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // Activate WCSession early so connectivity is ready before the first scene renders.
        _ = WCSessionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            StatusView()
                .task { await bootstrap() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func bootstrap() async {
        let ctx = container.mainContext

        // Fetch or create the single CalibrationData record for this device's store.
        let calibration = fetchOrCreateCalibration(in: ctx)

        // ── Step 7.1 wiring ─────────────────────────────────────────────────────
        SensorCoordinator.shared.calibration = calibration
        DrivingInterruptManager.shared.modelContext = ctx

        // Install the detection strategy now that CalibrationData exists.
        DetectionEngine.shared.install(strategy: HeuristicStrategy(calibration: calibration))
        // Hot-swap to a personalized model if one was delivered in a prior session.
        ModelManager.shared.loadSavedWeightsIfAvailable()

        // Route sensor vectors → detection; driving vectors → silent corpus log.
        SensorCoordinator.shared.onFeatureVector = { vector in
            DetectionEngine.shared.process(vector, mode: SensorCoordinator.shared.currentMode)
        }
        SensorCoordinator.shared.onSilentDrivingVector = { vector in
            DrivingInterruptManager.shared.logSilentVector(vector)
        }

        // Connect alert state machine, then start the sensor pipeline.
        AlertManager.shared.connectToDetectionEngine()
        SensorCoordinator.shared.startPassiveMonitoring()
    }

    @MainActor
    private func fetchOrCreateCalibration(in ctx: ModelContext) -> CalibrationData {
        if let existing = (try? ctx.fetch(FetchDescriptor<CalibrationData>()))?.first {
            return existing
        }
        let cal = CalibrationData()
        ctx.insert(cal)
        try? ctx.save()
        return cal
    }
}
