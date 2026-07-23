import SwiftUI
import WakemeShared

struct SettingsScreen: View {

    // Sensitivity feeds directly into HeuristicStrategy.sensitivityMultiplier.
    @AppStorage("sensitivityLevel")  private var sensitivity: Double = 3
    @AppStorage("thresholdPassive")  private var thresholdPassive: Double = 0.72
    @AppStorage("thresholdActive")   private var thresholdActive:  Double = 0.60

    @State private var showExport = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Detection

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $sensitivity, in: 1...5, step: 1)
                    }
                    Text("Higher sensitivity triggers alerts more easily. Lower sensitivity requires a stronger signal.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Detection")
                }

                Section {
                    HStack {
                        Text("Passive threshold")
                        Spacer()
                        Text(String(format: "%.2f", thresholdPassive))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $thresholdPassive, in: 0.5...0.95, step: 0.01)

                    HStack {
                        Text("Active session threshold")
                        Spacer()
                        Text(String(format: "%.2f", thresholdActive))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $thresholdActive, in: 0.4...0.85, step: 0.01)
                } header: {
                    Text("Detection thresholds")
                } footer: {
                    Text("Passive monitoring uses a higher threshold to reduce battery impact. Active sessions use a lower threshold for greater sensitivity.")
                }

                // MARK: Data

                Section("Data") {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                }

                // MARK: About

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Wakeme is a personal aid, not a medical device. Always consult your physician regarding narcolepsy diagnosis and treatment.")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
        }
    }

    private var sensitivityLabel: String {
        switch Int(sensitivity.rounded()) {
        case 1:  return "Low"
        case 2:  return "Medium-Low"
        case 3:  return "Medium"
        case 4:  return "Medium-High"
        default: return "High"
        }
    }
}
