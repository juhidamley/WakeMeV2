import SwiftUI
import WakemeShared

struct DrivingWarningView: View {
    var onAcknowledge: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                Text("Not a driving safety device")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Wakeme can't reliably detect a sleep attack in time to prevent an accident. Don't rely on it while driving. If you're at risk of a sleep attack, don't drive.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("I understand") { onAcknowledge() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
            .padding()
        }
        .interactiveDismissDisabled(true)   // must tap the button
    }
}
