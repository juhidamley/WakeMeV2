import SwiftUI
import SwiftData
import WakemeShared

struct AlertView: View {

    @Environment(\.modelContext) private var modelContext

    private var alert = AlertManager.shared

    // Digital Crown requires a bound Double. We watch it and dismiss on sufficient rotation.
    @State private var crownValue: Double = 0
    @State private var crownAccumulated: Double = 0

    private var currentStage: Int {
        if case .escalating(let stage, _) = alert.alertState { return stage }
        return 1
    }

    var body: some View {
        ZStack {
            PulsingRedBackground()
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Wake up")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.red)
                    .padding(.top, 4)

                Spacer(minLength: 2)

                StageIndicator(stage: currentStage, total: 4)

                Spacer(minLength: 2)

                VStack(spacing: 8) {
                    // "That was real" is the safety-important, high-value label → prominent.
                    Button {
                        dismiss(.confirmedAttack)
                    } label: {
                        Text("That was real")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button {
                        dismiss(.falseAlarm)
                    } label: {
                        Text("False alarm")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        // Digital Crown as a quick "false alarm" dismiss — someone waking and turning the crown.
        .focusable(true)
        .digitalCrownRotation(
            $crownValue,
            from: -100, through: 100, by: 1,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: crownValue) { oldValue, newValue in
            crownAccumulated += abs(newValue - oldValue)
            if crownAccumulated > 8 {   // meaningful deliberate turn, not a jostle
                crownAccumulated = 0
                dismiss(.falseAlarm)
            }
        }
        // An alert must not be swipeable away — dismissal is always a labeled choice.
        .interactiveDismissDisabled(true)
    }

    private func dismiss(_ type: DismissType) {
        alert.dismiss(as: type, modelContext: modelContext)
    }
}

// MARK: - Stage indicator (●●○○)

private struct StageIndicator: View {
    let stage: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < stage ? Color.red : Color.clear)
                    .overlay(Circle().stroke(Color.red.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityLabel("Alert stage \(stage) of \(total)")
    }
}

// MARK: - Pulsing background

private struct PulsingRedBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(now / 0.5 * .pi * 2) + 1) / 2   // fast pulse, matches escalation urgency
            let opacity = 0.10 + 0.12 * phase                  // 0.10 … 0.22
            Color.red.opacity(opacity)
        }
    }
}
