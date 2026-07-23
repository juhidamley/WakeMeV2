import SwiftUI
import SwiftData
import WakemeShared

struct MonitorScreen: View {

    @Environment(WCSessionManager.self) private var connectivity
    @Query(sort: \SleepAttackEvent.timestamp, order: .reverse) private var recentEvents: [SleepAttackEvent]

    @State private var showCeilingPicker = false
    @State private var selectedCeiling: EscalationCeiling = .fullAlarm

    private var isDriving: Bool { connectivity.watchStatus.activityContext == .automotive }
    private var isActive: Bool  { connectivity.watchStatus.mode == .active }

    private var todayCount: Int {
        recentEvents.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    // Days since the most recent confirmed attack — the user's current "safe" streak.
    private var streakDays: Int {
        guard let last = recentEvents.first(where: { $0.dismissType == .confirmedAttack }) else { return 0 }
        return Calendar.current.dateComponents([.day], from: last.timestamp, to: Date()).day ?? 0
    }

    private var hrText: String {
        connectivity.watchStatus.lastHeartRate.map { "\(Int($0)) bpm" } ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ringSection
                    metricsSection
                    if !isActive && !isDriving { startButton }
                    recentSection
                }
                .padding()
            }
            .navigationTitle("Wakeme")
            .sheet(isPresented: $showCeilingPicker) {
                CeilingPickerSheetiOS(selected: $selectedCeiling) {
                    // Step 6.2 will wire this command to the Watch.
                    WCSessionManager.shared.sendContext(["startSession": selectedCeiling.rawValue])
                }
            }
        }
    }

    // MARK: - Sections

    private var ringSection: some View {
        ZStack {
            MonitorRing(
                isActive: isActive,
                isDriving: isDriving,
                confidence: connectivity.watchStatus.confidence
            )
            .frame(width: 160, height: 160)

            VStack(spacing: 4) {
                if isDriving {
                    Image(systemName: "car.fill")
                        .font(.title)
                        .foregroundStyle(.gray)
                    Text("Not monitoring\nwhile driving")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text(isActive ? "Active" : "Monitoring").font(.headline)
                    Text(hrText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metricsSection: some View {
        HStack(spacing: 12) {
            MetricTile(title: "Today", value: "\(todayCount)")
            MetricTile(title: "Streak", value: "\(streakDays)d")
            MetricTile(title: "HR", value: hrText)
        }
    }

    private var startButton: some View {
        Button {
            selectedCeiling = .fullAlarm
            showCeilingPicker = true
        } label: {
            Label("Start session on Watch", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private var recentSection: some View {
        if recentEvents.isEmpty {
            ContentUnavailableView(
                "No events yet",
                systemImage: "moon.zzz",
                description: Text("Wear your Watch and start monitoring.")
            )
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                ForEach(recentEvents.prefix(3)) { event in
                    EventRow(event: event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Subviews

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).bold()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct EventRow: View {
    let event: SleepAttackEvent

    private var badge: String {
        switch event.dismissType {
        case .confirmedAttack: return "Confirmed"
        case .falseAlarm:      return "False alarm"
        case .noResponse:      return "No response"
        }
    }

    var body: some View {
        HStack {
            Text(event.timestamp, style: .time)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < event.severity ? Color.red : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text(badge).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MonitorRing: View {
    let isActive: Bool
    let isDriving: Bool
    let confidence: Double

    private var color: Color  { isDriving ? .gray : (isActive ? .teal : .gray) }
    private var period: Double { isDriving ? 4.0  : (isActive ? 1.5  : 3.0)  }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let now   = timeline.date.timeIntervalSinceReferenceDate
                let phase = (sin(now / period * .pi * 2) + 1) / 2
                let rect  = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)

                var ring = Path()
                ring.addEllipse(in: rect)
                ctx.stroke(ring, with: .color(color.opacity(0.4 + 0.4 * phase)), lineWidth: 8)

                if !isDriving, confidence > 0.01 {
                    var arc = Path()
                    arc.addArc(
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        radius: rect.width / 2,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 360 * min(max(confidence, 0), 1)),
                        clockwise: false
                    )
                    ctx.stroke(arc, with: .color(.teal), lineWidth: 4)
                }
            }
        }
    }
}

private struct CeilingPickerSheetiOS: View {
    @Binding var selected: EscalationCeiling
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func label(_ c: EscalationCeiling) -> String {
        switch c {
        case .silent:         return "Silent — screen only"
        case .hapticOnly:     return "Haptic only"
        case .hapticThenTone: return "Haptic, then subtle tone"
        case .fullAlarm:      return "Full alarm"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Alert level", selection: $selected) {
                    ForEach(EscalationCeiling.allCases, id: \.self) {
                        Text(label($0)).tag($0)
                    }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("Start session")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { onConfirm(); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
