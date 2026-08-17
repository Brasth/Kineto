import KinetoCore
import SwiftUI

struct MeetingChatComposer: View {
    @Bindable var model: AppModel
    @Binding var question: String
    var focused: FocusState<Bool>.Binding
    let editorHeight: CGFloat
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onOpenSettings: () -> Void

    private static let limit = 1_500

    var body: some View {
        let chatDisabled = !model.canAskCurrentMeeting
            || model.isGeneratingSummary
            || model.isAnsweringChat
        let questionIsEmpty = question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Ask Kineto", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.headline)

                Spacer(minLength: 8)

                Picker("AI provider", selection: $model.chatProvider) {
                    ForEach(ChatProviderID.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.systemImage)
                            .tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("AI provider")
            }

            Label(disclosure, systemImage: model.chatProvider.sendsMeetingExcerptsOffDevice ? "network" : "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(model.chatProvider.sendsMeetingExcerptsOffDevice ? Color.orange : Color.secondary)
                .accessibilityElement(children: .combine)

            if model.chatProvider.sendsMeetingExcerptsOffDevice, !model.selectedProviderConnected {
                Button("Connect \(model.chatProvider.displayName) in Settings…", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: boundedQuestion)
                    .font(.body)
                    .focused(focused)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: editorHeight)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator)
                    }
                    .disabled(chatDisabled)
                    .accessibilityLabel("Ask this meeting")
                    .accessibilityHint(
                        "Type a question about this meeting’s finalized transcript. Return adds a line. Command-Return sends."
                    )
                    .accessibilityValue(characterCountLabel)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        onSubmit()
                        return .handled
                    }

                if question.isEmpty {
                    Text("Ask a question about this meeting")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Return adds a line · ⌘↩ sends")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(question.count)/\(Self.limit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(question.count == Self.limit ? .orange : .secondary)
                    .accessibilityLabel(characterCountLabel)

                if model.isAnsweringChat {
                    Button("Stop", systemImage: "stop.fill", action: onStop)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .accessibilityLabel("Stop answer")
                } else {
                    Button("Send", systemImage: "paperplane.fill", action: onSubmit)
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .disabled(chatDisabled || questionIsEmpty || !model.selectedProviderReady)
                        .accessibilityLabel("Send question")
                        .accessibilityHint("Searches this meeting’s finalized transcript.")
                }
            }

            if question.count == Self.limit {
                Text("Limit reached")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isAnsweringChat {
            Text(model.chatProvider.sendsMeetingExcerptsOffDevice
                 ? "Sending retrieved excerpts to \(model.chatProvider.displayName)…"
                 : "Searching the finalized transcript…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.isGeneratingSummary {
            Text("Preparing the summary. Questions are available when it is complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !model.canAskCurrentMeeting {
            Text("Questions become available when the finalized transcript is ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !model.appleOnDeviceAvailable, model.chatProvider == .appleOnDevice {
            Text("On-this-Mac answers need macOS 26 with Apple Intelligence. Connect Grok, OpenAI, or Gemini, or upgrade.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var disclosure: String {
        if model.chatProvider.sendsMeetingExcerptsOffDevice {
            if model.selectedProviderConnected {
                return "Sent to \(model.chatProvider.displayName) · retrieved excerpts only"
            }
            return "\(model.chatProvider.displayName) is not connected"
        }
        return "On this Mac · finalized transcript only"
    }

    private var boundedQuestion: Binding<String> {
        Binding(
            get: { question },
            set: { question = String($0.prefix(Self.limit)) }
        )
    }

    private var characterCountLabel: String {
        let limitReached = question.count == Self.limit ? ", limit reached" : ""
        return "\(question.count) of \(Self.limit) characters\(limitReached)"
    }
}
