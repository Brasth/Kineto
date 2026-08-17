import KinetoCore
import SwiftUI

struct MeetingNotepadView: View {
    @Bindable var model: AppModel
    @Binding var evidenceSelection: EvidenceSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your notes")
                    .font(.headline)
                Spacer()
                if model.activeMeeting?.state == .stopped {
                    Button(model.isEnhancingRecap ? "Enhancing…" : "Enhance notes") {
                        model.enhanceRecap()
                    }
                    .disabled(model.isEnhancingRecap || model.isGeneratingSummary || model.isAnsweringChat)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if model.isRecapStale {
                Text("Notes changed since the last enhance. Enhance again to refresh transcript fills.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            TextEditor(text: $model.scratchpadDraft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Handwritten meeting notes")

            if let recap = model.recap {
                Divider()
                MeetingRecapView(
                    recap: recap,
                    model: model,
                    evidenceSelection: $evidenceSelection
                )
                .frame(minHeight: 160)
            }
        }
        .onChange(of: model.scratchpadDraft) { _, _ in
            model.scheduleScratchpadPersist()
        }
    }
}
