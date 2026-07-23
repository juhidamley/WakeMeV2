import SwiftUI
import SwiftData
import UIKit
import WakemeShared

struct ExportSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Query private var allEvents: [SleepAttackEvent]
    @Query private var falseNegatives: [FalseNegativeReport]

    @State private var range: ExportManager.Range = .days30
    @State private var isGenerating = false
    @State private var shareURL: URL?

    private let manager = ExportManager()

    private var eventsInRange: [SleepAttackEvent] {
        let interval = range.interval
        return allEvents
            .filter { interval.contains($0.timestamp) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Range") {
                    Picker("Range", selection: $range) {
                        ForEach(ExportManager.Range.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("\(eventsInRange.count) event\(eventsInRange.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            isGenerating = true
                            shareURL = await manager.generatePDF(
                                events: eventsInRange,
                                falseNegatives: Array(falseNegatives),
                                range: range
                            )
                            isGenerating = false
                        }
                    } label: {
                        Label("Export PDF report", systemImage: "doc.richtext")
                    }
                    .disabled(isGenerating)

                    Button {
                        shareURL = manager.generateCSV(events: eventsInRange)
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    .disabled(isGenerating)
                }

                if isGenerating {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Generating report…")
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - URL+Identifiable (for .sheet(item:))

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
