import KinetoCore
import SwiftUI

struct ChatTurnView: View {
    let turn: ChatTurnRecord
    let detail: String
    let excerpts: [EvidenceReference]
    let onSelectCitation: (EvidenceReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 48)
                Text(turn.question)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("You asked: \(turn.question)")
            }

            VStack(alignment: .leading, spacing: 8) {
                if turn.outcome == .grounded {
                    Text(turn.answer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !turn.citations.isEmpty {
                        citationRow(turn.citations, hint: "Opens the supporting finalized transcript excerpt.")
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if turn.noAnswerReason == .invalidGeneratedEvidence {
                        Text("Not saved as a meeting fact.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !excerpts.isEmpty {
                        Text("Related transcript excerpts — not an answer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if !turn.citations.isEmpty {
                        citationRow(turn.citations, hint: "Opens a related finalized transcript excerpt.")
                    }
                }

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    private var caption: String {
        let name = turn.provider?.displayName ?? "Kineto"
        let model = turn.provider?.defaultModel
        switch turn.outcome {
        case .grounded:
            if let model, turn.provider?.sendsMeetingExcerptsOffDevice == true {
                return "\(name) · \(model) · grounded"
            }
            return "\(name) · grounded"
        case .noAnswer:
            return "\(name) · no answer"
        }
    }

    private func citationRow(_ citations: [EvidenceReference], hint: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(citations.enumerated()), id: \.offset) { index, citation in
                Button("Evidence \(index + 1)", systemImage: "doc.text.magnifyingglass") {
                    onSelectCitation(citation)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(hint)
            }
        }
    }
}

struct ChatDraftTurnView: View {
    let question: String
    let provider: ChatProviderID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 48)
                Text(question)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(provider.sendsMeetingExcerptsOffDevice
                     ? "Asking \(provider.displayName)…"
                     : "Searching the finalized transcript…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("▌")
                    .font(.caption)
                    .foregroundStyle(.mint)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
