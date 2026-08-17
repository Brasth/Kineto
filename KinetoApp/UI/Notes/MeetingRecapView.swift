import KinetoCore
import SwiftUI

struct MeetingRecapView: View {
    let recap: MeetingRecapRecord
    let model: AppModel
    @Binding var evidenceSelection: EvidenceSelection?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recap.blocks.enumerated()), id: \.element.id) { index, block in
                    recapBlock(block, previous: index > 0 ? recap.blocks[index - 1] : nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Enhanced meeting notes")
    }

    @ViewBuilder
    private func recapBlock(_ block: RecapBlock, previous: RecapBlock?) -> some View {
        switch block.kind {
        case .user:
            Text(block.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, previous?.kind == .filled ? 8 : 2)
                .accessibilityLabel("Your note. \(block.text)")
        case .filled:
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(Color.mint.opacity(0.85))
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("From the transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                    Text(block.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !block.evidence.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(block.evidence.enumerated()), id: \.offset) { _, evidence in
                                Button("Evidence") {
                                    if let segment = model.segments.first(where: { $0.id == evidence.segmentID }) {
                                        evidenceSelection = EvidenceSelection(
                                            segment: segment,
                                            supportingText: evidence.supportingText
                                        )
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 4)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Inserted from transcript. \(block.text)")
        }
    }
}
