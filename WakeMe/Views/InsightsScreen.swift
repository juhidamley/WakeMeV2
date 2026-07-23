import SwiftUI
import SwiftData
import Charts
import WakemeShared

struct InsightsScreen: View {

    @Query(sort: \SleepAttackEvent.timestamp, order: .reverse) private var events: [SleepAttackEvent]
    @Query private var falseNegatives: [FalseNegativeReport]
    @Query(sort: \ModelVersion.version, order: .reverse) private var modelVersions: [ModelVersion]

    @Environment(\.modelContext) private var modelContext
    @State private var showExport = false
    @State private var personalizationManager: PersonalizationManager?

    // MARK: - Derived

    private var confirmedAttacks: [SleepAttackEvent] {
        events.filter { $0.dismissType == .confirmedAttack }
    }
    private var falseAlarms: [SleepAttackEvent] {
        events.filter { $0.dismissType == .falseAlarm }
    }
    private var confirmedCount: Int { confirmedAttacks.count }
    private var falseAlarmCount: Int { falseAlarms.count }

    // Real Phase 9 gate — must match PersonalizationManager.isReadyToTrain exactly.
    private var canTrain: Bool { confirmedCount >= 10 && falseAlarmCount >= 5 }
    private var labeledCount: Int { confirmedCount + falseAlarmCount }

    private var deployedModel: ModelVersion? { modelVersions.first(where: { $0.isDeployed }) }
    private var modelLabel: String {
        if let m = deployedModel, m.isPersonalized { return "Personalized model v\(m.version)" }
        return "Generic model v\(deployedModel?.version ?? 1) (heuristic)"
    }

    // Recall = detected confirmed / (detected confirmed + missed)
    private var missedCount: Int { falseNegatives.count }
    private var knownAttacks: Int { confirmedCount + missedCount }
    private var recall: Double {
        knownAttacks == 0 ? 0 : Double(confirmedCount) / Double(knownAttacks)
    }

    // Hour buckets for the bar chart, one row per (hour, mode) pair.
    private struct HourBucket: Identifiable {
        let id = UUID()
        let hour: Int
        let mode: SessionMode
        let count: Int
    }

    private var hourBuckets: [HourBucket] {
        var map: [String: Int] = [:]
        for e in confirmedAttacks {
            let h = Calendar.current.component(.hour, from: e.timestamp)
            let key = "\(h)-\(e.monitoringMode.rawValue)"
            map[key, default: 0] += 1
        }
        return map.compactMap { key, count in
            let parts = key.split(separator: "-")
            guard let h = Int(parts[0]),
                  let mode = SessionMode(rawValue: String(parts[1]))
            else { return nil }
            return HourBucket(hour: h, mode: mode, count: count)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    riskByHourSection
                    modelStatusCard
                    recallCard
                }
                .padding()
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showExport) {
                ExportSheet()
            }
            .task {
                if personalizationManager == nil {
                    personalizationManager = PersonalizationManager(modelContext: modelContext)
                }
            }
        }
    }

    // MARK: - Risk by hour

    private var riskByHourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attack frequency by hour").font(.headline)
            if confirmedAttacks.isEmpty {
                Text("No confirmed attacks yet. This chart fills in as you confirm real events.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart(hourBuckets) { bucket in
                    BarMark(
                        x: .value("Hour", bucket.hour),
                        y: .value("Events", bucket.count)
                    )
                    .foregroundStyle(by: .value("Mode", bucket.mode == .active ? "Active" : "Passive"))
                }
                .chartForegroundStyleScale(["Passive": Color.gray, "Active": Color.teal])
                .chartXScale(domain: 0...24)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) { Text("\(h)") }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Model status card

    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detection model").font(.headline)
            Text(modelLabel).font(.subheadline).foregroundStyle(.secondary)

            if !(deployedModel?.isPersonalized ?? false) {
                ProgressView(value: Double(min(labeledCount, 15)), total: 15) {
                    Text("\(labeledCount) of ~15 labeled events").font(.caption)
                }

                Text("Confirmed: \(confirmedCount)/10 · False alarms: \(falseAlarmCount)/5")
                    .font(.caption2).foregroundStyle(.secondary)

                Text("Dismiss each alert as 'real' or 'false alarm' in History to collect labels.")
                    .font(.caption).foregroundStyle(.secondary)

                if let manager = personalizationManager, manager.isTraining {
                    ProgressView(value: manager.trainingProgress) {
                        Text("Training… \(Int(manager.trainingProgress * 100))%").font(.caption)
                    }
                } else {
                    Button("Train personalized model") {
                        if let manager = personalizationManager {
                            Task { await manager.startTraining() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canTrain || personalizationManager == nil)

                    if !canTrain {
                        Text("Available once you have at least 10 confirmed attacks and 5 false alarms.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let err = personalizationManager?.lastTrainingError {
                    Text("Training error: \(err)").font(.caption2).foregroundStyle(.red)
                }
                if let v = personalizationManager?.lastTrainedVersion {
                    Label("Model v\(v) trained — delivering to Watch", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            } else {
                Label("Personalized and active", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recall card

    private var recallCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detection recall").font(.headline)
            if knownAttacks == 0 {
                Text("No confirmed or missed attacks logged yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Detected \(confirmedCount) of \(knownAttacks) known attacks (\(Int(recall * 100))%)")
                    .font(.subheadline)
                ProgressView(value: recall)
                Text("Log attacks Wakeme missed (in History) to keep this honest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

