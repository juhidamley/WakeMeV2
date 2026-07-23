import SwiftUI
import SwiftData
import WakemeShared

struct StatusView: View {

    @Environment(\.modelContext) private var modelContext

    // Referencing @Observable properties in body establishes observation automatically (iOS 17+).
    private var alert = AlertManager.shared
    private var sensors = SensorCoordinator.shared
    private var engine = DetectionEngine.shared
    private var connectivity = WCSessionManager.shared
    private var driving = DrivingInterruptManager.shared

    @State private var showCeilingPicker = false
    @State private var selectedCeiling: EscalationCeiling = .fullAlarm
    @State private var isBusy = false

    private var isEscalating: Bool {
        if case .escalating = alert.alertState { return true }
        return false
    }
    private var isActiveSession: Bool { sensors.currentMode == .active }

    private var statusText: String {
        if driving.isInAutomotiveContext { return "Not monitoring\n— driving" }
        if isEscalating { return "Detecting…" }
        return isActiveSession ? "Active session" : "Monitoring"
    }

    private var hrText: String {
        if let hr = connectivity.watchStatus.lastHeartRate, hr > 0 {
            return "♥ \(Int(hr)) bpm"
        }
        return "♥ —"
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                StatusRing(
                    state: alert.alertState,
                    isActive: isActiveSession,
                    isDriving: driving.isInAutomotiveContext,
                    confidence: engine.currentConfidence
                )
                .frame(width: 120, height: 120)

                VStack(spacing: 2) {
                    if driving.isInAutomotiveContext {
                        Image(systemName: "car.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.gray)
                    }
                    Text(statusText)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(hrText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isActiveSession {
                Button(role: .destructive) {
                    endSession()
                } label: {
                    Text("End session").frame(maxWidth: .infinity)
                }
                .disabled(isBusy)
            } else {
                Button {
                    selectedCeiling = .fullAlarm
                    showCeilingPicker = true
                } label: {
                    Text("Start session").frame(maxWidth: .infinity)
                }
                .disabled(isBusy)
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showCeilingPicker) {
            CeilingPickerSheet(selected: $selectedCeiling) {
                startSession(ceiling: selectedCeiling)
            }
        }
        .sheet(isPresented: Binding(
            get: { driving.showsDrivingWarning },
            set: { driving.showsDrivingWarning = $0 }
        )) {
            DrivingWarningView {
                driving.showsDrivingWarning = false
            }
        }
        .fullScreenCover(isPresented: .constant(isEscalating)) {
            AlertView()
        }
    }

    private func startSession(ceiling: EscalationCeiling) {
        showCeilingPicker = false
        isBusy = true
        Task {
            try? await sensors.startActiveSession(
                mode: .active,
                escalationCeiling: ceiling,
                modelContext: modelContext
            )
            isBusy = false
        }
    }

    private func endSession() {
        isBusy = true
        Task {
            await sensors.stopActiveSession(modelContext: modelContext)
            isBusy = false
        }
    }
}

// MARK: - Status ring

private struct StatusRing: View {
    let state: AlertState
    let isActive: Bool
    let isDriving: Bool
    let confidence: Double

    private var ringColor: Color {
        if isDriving { return .gray }
        if case .escalating = state { return .red }
        return isActive ? .teal : .gray
    }

    private var pulsePeriod: Double {
        if case .escalating = state { return 0.4 }
        return isActive ? 1.5 : 3.0
    }

    private var opacityRange: ClosedRange<Double> {
        if case .escalating = state { return 0.9...1.0 }
        return isActive ? 0.6...1.0 : 0.4...0.7
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let phase = (sin(now / pulsePeriod * .pi * 2) + 1) / 2  // 0…1
                let opacity = opacityRange.lowerBound
                    + (opacityRange.upperBound - opacityRange.lowerBound) * phase

                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)

                // Base ring
                var ring = Path()
                ring.addEllipse(in: rect)
                context.stroke(ring, with: .color(ringColor.opacity(opacity)), lineWidth: 6)

                // Confidence arc (teal), drawn clockwise from top — only when not escalating or driving
                if confidence > 0.01, !state.isEscalatingCase, !isDriving {
                    let startAngle = Angle(degrees: -90)
                    let endAngle = Angle(degrees: -90 + 360 * min(max(confidence, 0), 1))
                    var arc = Path()
                    arc.addArc(
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        radius: rect.width / 2,
                        startAngle: startAngle,
                        endAngle: endAngle,
                        clockwise: false
                    )
                    context.stroke(arc, with: .color(.teal), lineWidth: 3)
                }
            }
        }
    }
}

private extension AlertState {
    var isEscalatingCase: Bool {
        if case .escalating = self { return true }
        return false
    }
}

// MARK: - Ceiling picker sheet

private struct CeilingPickerSheet: View {
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
        VStack {
            Text("Alert level").font(.headline)
            Picker("Alert level", selection: $selected) {
                ForEach(EscalationCeiling.allCases, id: \.self) {
                    Text(label($0)).tag($0)
                }
            }
            .labelsHidden()

            Button("Start") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

