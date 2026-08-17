import KinetoCore
import SwiftUI

struct MeetingChatView: View {
    @Bindable var model: AppModel
    @Binding var evidenceSelection: EvidenceSelection?
    var showsSourceStrip: Bool = false
    var onOpenSettings: () -> Void = {}

    @State private var chatQuestion = ""
    @FocusState private var chatQuestionFocused: Bool
    @ScaledMetric(relativeTo: .body) private var chatEditorHeight = 36
    @State private var submittedChatQuestion: String?

    var body: some View {
        VStack(spacing: 0) {
            if showsSourceStrip {
                sourceStrip
                Divider()
            }

            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Divider()
                MeetingChatComposer(
                    model: model,
                    question: $chatQuestion,
                    focused: $chatQuestionFocused,
                    editorHeight: chatEditorHeight,
                    onSubmit: submitChatQuestion,
                    onStop: { model.stopCurrentChat() },
                    onOpenSettings: onOpenSettings
                )
                .padding(8)
            }
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.isAnsweringChat) { _, isAnswering in
            if isAnswering {
                chatQuestionFocused = false
            } else if model.errorMessage == nil {
                submittedChatQuestion = nil
            }
        }
        .onChange(of: model.errorMessage) { _, message in
            if message != nil {
                restoreSubmittedQuestion()
            }
        }
        .onChange(of: model.pendingChatEgress) { _, pending in
            if pending == nil, !model.isAnsweringChat {
                restoreSubmittedQuestion()
            }
        }
    }

    private var sourceStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(sourceStripTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Source transcript strip")
    }

    private var sourceStripTitle: String {
        if let last = model.chatTurns.last?.citations.first,
           let segment = model.segments.first(where: { $0.id == last.segmentID }) {
            return segment.text
        }
        if let last = model.segments.last {
            return last.text
        }
        return "Open the Original Transcript tab to read the source."
    }

    @ViewBuilder
    private var conversation: some View {
        if model.chatTurns.isEmpty, !model.isAnsweringChat {
            ScrollView {
                VStack(spacing: 16) {
                    emptyState
                    suggestions
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.chatTurns) { turn in
                            ChatTurnView(
                                turn: turn,
                                detail: model.chatNoAnswerDetail(turn),
                                excerpts: model.chatNoAnswerExcerpts(turn),
                                onSelectCitation: selectCitation
                            )
                            .id(turn.id)
                        }
                        if model.isAnsweringChat, let submittedChatQuestion {
                            ChatDraftTurnView(
                                question: submittedChatQuestion,
                                provider: model.chatProvider
                            )
                            .id("draft")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.chatTurns.count) { _, _ in
                    scrollToLatest(using: proxy)
                }
                .onChange(of: model.isAnsweringChat) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.chatProvider.systemImage)
                .font(.title2)
                .foregroundStyle(.mint)
            Text("Ask this meeting")
                .font(.headline)
            Text(emptyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(.top, 24)
    }

    private var emptyDetail: String {
        if model.chatProvider.sendsMeetingExcerptsOffDevice {
            return "\(model.chatProvider.displayName) will see this question and retrieved excerpts only, after you allow it."
        }
        return "Answers stay on this Mac and must quote the finalized transcript."
    }

    private var suggestions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                suggestionButton("What decisions were made?")
                suggestionButton("What should happen next?")
                suggestionButton("What remains unresolved?")
            }
            VStack(spacing: 8) {
                suggestionButton("What decisions were made?")
                suggestionButton("What should happen next?")
                suggestionButton("What remains unresolved?")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func suggestionButton(_ question: String) -> some View {
        Button(question) {
            chatQuestion = question
            if model.canAskCurrentMeeting, !model.isGeneratingSummary, !model.isAnsweringChat {
                chatQuestionFocused = true
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityHint("Adds this prompt to the Ask Kineto composer.")
    }

    private func selectCitation(_ citation: EvidenceReference) {
        if let selection = model.citationSelection(for: citation) {
            evidenceSelection = EvidenceSelection(
                segment: selection.0,
                supportingText: selection.1
            )
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        let target: AnyHashable = model.isAnsweringChat ? "draft" : (model.chatTurns.last?.id ?? "draft")
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    private func submitChatQuestion() {
        let question = chatQuestion
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.canAskCurrentMeeting,
              !model.isGeneratingSummary,
              !model.isAnsweringChat else {
            return
        }
        submittedChatQuestion = question
        model.askCurrentMeeting(question: question)
        if model.isAnsweringChat || model.pendingChatEgress != nil {
            chatQuestion = ""
            chatQuestionFocused = false
        }
    }

    private func restoreSubmittedQuestion() {
        guard let submittedChatQuestion else { return }
        defer { self.submittedChatQuestion = nil }
        guard chatQuestion.isEmpty else { return }
        chatQuestion = submittedChatQuestion
        if model.canAskCurrentMeeting, !model.isGeneratingSummary, !model.isAnsweringChat {
            chatQuestionFocused = true
        }
    }
}
