import AppKit
import KinetoCore
import SwiftUI

struct ChatProviderSettingsView: View {
    @Bindable var model: AppModel
    @State private var draftKeys: [ChatProviderID: String] = [:]
    @State private var busyProvider: ChatProviderID?
    @State private var statusMessage: String?

    var body: some View {
        Section("AI providers") {
            Picker("Default for Ask and summary", selection: $model.chatProvider) {
                ForEach(ChatProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)

            Toggle("Ask before sending excerpts off this Mac", isOn: $model.alwaysAskBeforeEgress)

            Text("Meeting text is sent only after you ask, and only retrieved excerpts. The main app still has no network entitlement; an isolated helper makes the request.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ChatProviderID.allCases) { provider in
                providerRow(provider)
            }

            Text(ChatOAuthScaffold.officialSignInStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func providerRow(_ provider: ChatProviderID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.displayName, systemImage: provider.systemImage)
                    .font(.headline)
                Spacer()
                Text(model.accountHint(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(provider.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if provider == .appleOnDevice {
                Text(model.appleOnDeviceAvailable
                     ? "Available as the offline fallback on this Mac."
                     : "Requires macOS 26 with Apple Intelligence. Whisper and connected cloud providers still work.")
                    .font(.caption)
                    .foregroundStyle(model.appleOnDeviceAvailable ? .secondary : .orange)
            } else {
                SecureField("API key", text: draftBinding(for: provider))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Get key…") {
                        NSWorkspace.shared.open(provider.consoleURL)
                    }
                    .buttonStyle(.bordered)
                    Button(model.isProviderConnected(provider) ? "Replace key" : "Connect") {
                        Task { await connect(provider) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .disabled(busyProvider != nil)
                    if model.isProviderConnected(provider) {
                        Button("Disconnect", role: .destructive) {
                            Task { await model.disconnectChatProvider(provider) }
                        }
                        .disabled(busyProvider != nil)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func draftBinding(for provider: ChatProviderID) -> Binding<String> {
        Binding(
            get: { draftKeys[provider, default: ""] },
            set: { draftKeys[provider] = $0 }
        )
    }

    private func connect(_ provider: ChatProviderID) async {
        busyProvider = provider
        defer { busyProvider = nil }
        do {
            try await model.connectChatProvider(provider, apiKey: draftKeys[provider, default: ""])
            draftKeys[provider] = ""
            statusMessage = "\(provider.displayName) key stored in the Keychain on this Mac."
        } catch {
            statusMessage = "Could not store the \(provider.displayName) key."
        }
    }
}
