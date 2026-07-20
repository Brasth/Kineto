import SwiftUI
struct SignalGateMenu: View {
    let presentation: SignalGatePresentation
    let resetCaptionPosition: @MainActor () -> Void
    let performAction: @MainActor (SignalGateAction) -> Void

    var body: some View {
        Text(statusText)
            .foregroundStyle(.secondary)

        Divider()

        Text("Processed on this Mac")
        Text("Raw audio off for this meeting")


        Button("Reset Caption Position") {
            resetCaptionPosition()
        }
        if presentation.isActionAvailable(.pauseOrResume) || presentation.isActionAvailable(.stop) {
            Divider()

            if presentation.isActionAvailable(.pauseOrResume) {
                Button(presentation.phase == .paused ? "Resume Capture" : "Pause Capture") {
                    performAction(.pauseOrResume)
                }
            }

            if presentation.isActionAvailable(.stop) {
                Button("Stop & Process") {
                    performAction(.stop)
                }
            }
        }

        if presentation.isActionAvailable(.showMeetingDetails) {
            Divider()

            Button("Show Meeting Details") {
                performAction(.showMeetingDetails)
            }
        }
    }

    private var statusText: String {
        switch presentation.phase {
        case .hidden:
            "Kineto inactive"
        case .capturing:
            "Capturing"
        case .paused:
            "Capture paused"
        case .draining:
            "Finishing capture"
        case .processing:
            "Processing locally"
        }
    }
}

struct SignalGateGlyph: View {
    let phase: SignalGatePhase
    let accessibilityValue: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("K")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 14, height: 14, alignment: .leading)

            phaseIndicator
                .frame(width: 4, height: 4)
        }
        .frame(width: 18, height: 18)
        .foregroundStyle(.primary)
        .accessibilityLabel("Kineto status")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .capturing:
            Circle()
                .fill(.primary)
        case .paused:
            Circle()
                .stroke(.primary, lineWidth: 1.25)
        case .draining:
            Capsule()
                .fill(.primary)
        case .processing:
            RoundedRectangle(cornerRadius: 0.75)
                .stroke(.primary, lineWidth: 1.25)
                .rotationEffect(.degrees(45))
        }
    }
}
