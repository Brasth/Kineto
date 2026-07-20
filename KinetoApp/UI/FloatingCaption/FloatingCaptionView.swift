import SwiftUI

struct FloatingCaptionView: View {
    let presentation: FloatingCaptionPresentation
    let isContentSuppressed: Bool
    let signalGatePresentation: SignalGatePresentation
    let width: CGFloat
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void
    let onActionIntent: (SignalGateAction) -> Void

    init(
        presentation: FloatingCaptionPresentation,
        width: CGFloat,
        signalGatePresentation: SignalGatePresentation = SignalGatePresentation(phase: .hidden),
        isContentSuppressed: Bool = false,
        onPanelDragChanged: @escaping (CGSize) -> Void = { _ in },
        onPanelDragEnded: @escaping () -> Void = {},
        onActionIntent: @escaping (SignalGateAction) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.signalGatePresentation = signalGatePresentation
        self.width = width
        self.isContentSuppressed = isContentSuppressed
        self.onPanelDragChanged = onPanelDragChanged
        self.onPanelDragEnded = onPanelDragEnded
        self.onActionIntent = onActionIntent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FloatingCaptionHeaderView(
                presentation: presentation.header,
                onPanelDragChanged: onPanelDragChanged,
                onPanelDragEnded: onPanelDragEnded
            )

            FloatingCaptionControlsView(
                presentation: signalGatePresentation,
                onActionIntent: onActionIntent
            )

            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                ForEach(presentation.lines) { line in
                    FloatingCaptionLineView(
                        line: line,
                        isActive: line.id == presentation.activeLineID
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 68,
                alignment: .bottomLeading
            )
            .allowsHitTesting(false)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: width, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.3))
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isContentSuppressed ? 0 : 1)
        .allowsHitTesting(!isContentSuppressed)
        .accessibilityHidden(isContentSuppressed)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct FloatingCaptionHeaderView: View {
    let presentation: FloatingCaptionHeaderPresentation
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(presentation.captureStatus.title, systemImage: presentation.captureStatus.symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(
                    presentation.captureStatus == .capturing
                        ? Color.red.opacity(0.82)
                        : Color.secondary
                )
                .accessibilityLabel("Capture status: \(presentation.captureStatus.title)")

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { onPanelDragChanged($0.translation) }
                .onEnded { _ in onPanelDragEnded() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Caption capture header")
        .accessibilityHint("Drag this header to move captions.")
    }

}

private struct FloatingCaptionControlsView: View {
    let presentation: SignalGatePresentation
    let onActionIntent: (SignalGateAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                pauseButton
                stopButton
                meetingDetailsButton
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    pauseButton
                    stopButton
                }
                meetingDetailsButton
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption.weight(.medium))
    }

    @ViewBuilder
    private var pauseButton: some View {
        if presentation.isActionAvailable(.pauseOrResume) {
            Button {
                onActionIntent(.pauseOrResume)
            } label: {
                Label("Pause", systemImage: "pause.fill")
                    .frame(minHeight: 28)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Pause capture")
            .accessibilityHint("Temporarily pauses this meeting capture.")
        }
    }

    @ViewBuilder
    private var stopButton: some View {
        if presentation.isActionAvailable(.stop) {
            Button {
                onActionIntent(.stop)
            } label: {
                Label("Stop & Process", systemImage: "stop.fill")
                    .frame(minHeight: 28)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Stop and process meeting")
            .accessibilityHint("Stops capture and begins local meeting processing.")
        }
    }

    @ViewBuilder
    private var meetingDetailsButton: some View {
        if presentation.isActionAvailable(.showMeetingDetails) {
            Button {
                onActionIntent(.showMeetingDetails)
            } label: {
                Label("Show Meeting Details", systemImage: "macwindow")
                    .frame(minHeight: 28)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Show meeting details")
            .accessibilityHint("Reveals the current live meeting window.")
        }
    }
}

private struct FloatingCaptionLineView: View {
    let line: FloatingCaptionLine
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(line.sourceLabel)
                    .font(.caption2.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(.secondary)
                if isActive {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.mint)
                }
            }

            Text(line.text)
                .font(isActive ? .title3.weight(.semibold) : .body)
                .foregroundStyle(
                    isActive ? Color.mint : (line.isVolatile ? .secondary : .primary)
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = line.translation {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var components = [
            line.sourceLabel,
            isActive ? "Live caption" : (line.isVolatile ? "Provisional caption" : "Final caption"),
            "Original: \(line.text)"
        ]
        if let translation = line.translation { components.append("Translation: \(translation)") }
        return components.joined(separator: ". ")
    }
}
