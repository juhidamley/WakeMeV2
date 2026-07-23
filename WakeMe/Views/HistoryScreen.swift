import SwiftUI
import SwiftData
import WakemeShared

struct HistoryScreen: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SleepAttackEvent.timestamp, order: .reverse) private var events: [SleepAttackEvent]

    @State private var selectedDate: Date? = nil
    @State private var filterDismiss: DismissType? = nil
    @State private var filterMode: SessionMode? = nil
    @State private var showFilters = false
    @State private var showLogMissed = false
    @State private var reviewTarget: SleepAttackEvent? = nil

    // Events needing retrospective review: noResponse and not yet reclassified.
    private var pendingReview: [SleepAttackEvent] {
        events.filter { $0.dismissType == .noResponse && !$0.wasReclassified }
    }

    private var filteredEvents: [SleepAttackEvent] {
        events.filter { e in
            if let d = selectedDate, !Calendar.current.isDate(e.timestamp, inSameDayAs: d) { return false }
            if let fd = filterDismiss, e.dismissType != fd { return false }
            if let fm = filterMode, e.monitoringMode != fm { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CalendarHeatmap(events: events, selectedDate: $selectedDate)

                    if !pendingReview.isEmpty {
                        reviewBanner
                    }

                    eventList
                }
                .padding()
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLogMissed = true } label: {
                        Label("Log missed", systemImage: "plus.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(dismiss: $filterDismiss, mode: $filterMode)
            }
            .sheet(isPresented: $showLogMissed) {
                LogMissedAttackSheet { date, notes in
                    let report = FalseNegativeReport(approxTimestamp: date, notes: notes)
                    modelContext.insert(report)
                    try? modelContext.save()
                }
            }
            .sheet(item: $reviewTarget) { event in
                ReviewSheet(event: event) { resolved in
                    reclassify(event, to: resolved)
                }
            }
        }
    }

    // MARK: - Retrospective review banner

    private var reviewBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(pendingReview.count) event\(pendingReview.count == 1 ? "" : "s") need review",
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.subheadline).bold()
            .foregroundStyle(.orange)

            Text("These alerts ended with no response. Was it a real attack the alarm didn't wake you from, or a false alarm you ignored?")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(pendingReview.prefix(5)) { event in
                Button { reviewTarget = event } label: {
                    HStack {
                        Text(event.timestamp, format: .dateTime.month().day().hour().minute())
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // Preserves originalDismissType only on the first reclassification so repeated edits
    // don't overwrite the true original label.
    private func reclassify(_ event: SleepAttackEvent, to type: DismissType) {
        if event.originalDismissType == nil {
            event.originalDismissType = event.dismissType
        }
        event.dismissType = type
        event.wasReclassified = true
        try? modelContext.save()
        reviewTarget = nil
    }

    // MARK: - Event list

    @ViewBuilder private var eventList: some View {
        if filteredEvents.isEmpty {
            ContentUnavailableView(
                "No events",
                systemImage: "moon.zzz",
                description: Text(selectedDate == nil ? "No events recorded yet." : "No events on this day.")
            )
        } else {
            VStack(spacing: 0) {
                if selectedDate != nil || filterDismiss != nil || filterMode != nil {
                    Button("Clear filters") {
                        selectedDate = nil; filterDismiss = nil; filterMode = nil
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 4)
                }
                ForEach(filteredEvents) { event in
                    HistoryEventRow(event: event)
                        .swipeActions(edge: .trailing) {
                            if event.dismissType == .falseAlarm {
                                Button("It was real") {
                                    reclassify(event, to: .confirmedAttack)
                                }.tint(.red)
                            } else if event.dismissType == .confirmedAttack {
                                Button("False alarm") {
                                    reclassify(event, to: .falseAlarm)
                                }.tint(.gray)
                            }
                        }
                    Divider()
                }
            }
        }
    }
}

// MARK: - Calendar heatmap

private struct CalendarHeatmap: View {
    let events: [SleepAttackEvent]
    @Binding var selectedDate: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // 35 days (5 weeks), oldest first.
    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<35).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func count(on day: Date) -> Int {
        events.filter { Calendar.current.isDate($0.timestamp, inSameDayAs: day) }.count
    }

    private func color(for c: Int) -> Color {
        switch c {
        case 0:    return Color(.secondarySystemBackground)
        case 1...2: return .orange.opacity(0.4)
        default:   return .orange.opacity(0.85)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 5 weeks").font(.headline)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let c = count(on: day)
                    let isSelected = selectedDate.map {
                        Calendar.current.isDate($0, inSameDayAs: day)
                    } ?? false
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: c))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.primary : .clear, lineWidth: 2)
                        )
                        .overlay(
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.system(size: 9))
                                .foregroundStyle(c > 0 ? .white : .secondary)
                        )
                        .onTapGesture {
                            selectedDate = isSelected ? nil : day
                        }
                }
            }
        }
    }
}

// MARK: - Event row

private struct HistoryEventRow: View {
    let event: SleepAttackEvent

    private var dismissBadge: (String, Color) {
        switch event.dismissType {
        case .confirmedAttack: return ("Confirmed", .red)
        case .falseAlarm:      return ("False alarm", .gray)
        case .noResponse:      return ("No response", .orange)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.timestamp, format: .dateTime.hour().minute())
                Text(event.timestamp, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < event.severity ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                    Text(durationText)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Badge(text: event.monitoringMode == .active ? "Active" : "Passive", color: .blue)
                    Badge(text: dismissBadge.0, color: dismissBadge.1)
                    if event.wasReclassified {
                        Badge(text: "Reclassified", color: .purple)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var durationText: String {
        let s = Int(event.duration)
        return s >= 60 ? "\(s/60)m \(s%60)s" : "\(s)s"
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Sheets

private struct ReviewSheet: View {
    let event: SleepAttackEvent
    let onResolve: (DismissType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(event.timestamp, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.headline)
                Text("This alert escalated to stage \(event.severity) but got no response. What happened?")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                Button {
                    onResolve(.confirmedAttack); dismiss()
                } label: {
                    Text("It was a real attack — the alarm didn't wake me")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)

                Button {
                    onResolve(.falseAlarm); dismiss()
                } label: {
                    Text("False alarm — I ignored it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Review event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
    }
}

private struct LogMissedAttackSheet: View {
    let onSave: (Date, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var when = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("When did it happen?") {
                    DatePicker("Approximate time", selection: $when, in: ...Date())
                }
                Section("Notes (optional)") {
                    TextField("What were you doing?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("Logging attacks Wakeme missed helps measure how often detection fails, and improves your personal model.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log missed attack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(when, notes.isEmpty ? nil : notes); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct FilterSheet: View {
    @Binding var dismiss: DismissType?
    @Binding var mode: SessionMode?
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            Form {
                Section("Dismiss type") {
                    Picker("Type", selection: $dismiss) {
                        Text("All").tag(DismissType?.none)
                        Text("Confirmed").tag(DismissType?.some(.confirmedAttack))
                        Text("False alarm").tag(DismissType?.some(.falseAlarm))
                        Text("No response").tag(DismissType?.some(.noResponse))
                    }
                }
                Section("Mode") {
                    Picker("Mode", selection: $mode) {
                        Text("All").tag(SessionMode?.none)
                        Text("Passive").tag(SessionMode?.some(.passive))
                        Text("Active").tag(SessionMode?.some(.active))
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismissSheet() }
                }
            }
        }
    }
}
