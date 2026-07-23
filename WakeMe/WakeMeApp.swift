import SwiftUI
import SwiftData
import WakemeShared

@main
struct WakeMeApp: App {

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
            MainTabView()
                .environment(WCSessionManager.shared)
                .task { await bootstrap() }
        }
        .modelContainer(container)
    }

    @MainActor
    private func bootstrap() async {
        let ctx = container.mainContext

        // Give WatchConnectivity the context so received events persist (Step 6.1).
        WCSessionManager.shared.modelContext = ctx

        let calibration = fetchOrCreateCalibration(in: ctx)

        // Refresh HealthKit baselines on first launch or if data is older than 7 days.
        let stale = calibration.healthKitLastQueried
            .map { Date().timeIntervalSince($0) > 7 * 24 * 3600 } ?? true
        if stale {
            await HealthKitBaselineManager.shared.refreshBaselines(calibration: calibration)
            try? ctx.save()
        }
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
