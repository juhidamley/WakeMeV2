import SwiftUI
import WakemeShared

struct MainTabView: View {
    var body: some View {
        TabView {
            MonitorScreen()
                .tabItem { Label("Monitor", systemImage: "heart.fill") }
            HistoryScreen()
                .tabItem { Label("History", systemImage: "clock.fill") }
            InsightsScreen()
                .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
