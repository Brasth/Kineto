import KinetoCore
import SwiftUI

struct ChatEgressConsentSheet: View {
    let provider: ChatProviderID
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Send retrieved excerpts?", systemImage: "network")
                .font(.title2.weight(.semibold))

            Text(ChatProviderPreferences.consentDisclosure(for: provider))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Kineto does not send the full meeting, audio, other meetings, or encryption keys.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send to \(provider.displayName)", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460)
    }
}
