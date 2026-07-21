import SwiftUI

struct FloatingCaptionView: View {
    let presentation: FloatingCaptionPresentation
    let isContentSuppressed: Bool
    let signalGatePresentation: SignalGatePresentation
    let width: CGFloat
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void
    let onActionIntent: (SignalGateAction) -> Void
    let emphasizeEntrance: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        presentation: FloatingCaptionPresentation,
        width: CGFloat,
        signalGatePresentation: SignalGatePresentation = SignalGatePresentation(phase: .hidden),
        isContentSuppressed: Bool = false,
        emphasizeEntrance: Bool = false,
        onPanelDragChanged: @escaping (CGSize) -> Void = { _ in },
        onPanelDragEnded: @escaping () -> Void = {},
        onActionIntent: @escaping (SignalGateAction) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.signalGatePresentation = signalGatePresentation
        self.width = width
        self.isContentSuppressed = isContentSuppressed
        self.emphasizeEntrance = emphasizeEntrance
        self.onPanelDragChanged = onPanelDragChanged
        self.onPanelDragEnded = onPanelDragEnded
        self.onActionIntent = onActionIntent
    }

    var body: some View {
        let isEmphasized = emphasizeEntrance

        VStack(alignment: .leading, spacing: 0) {
            // Dedicated drag handle bar at the very top – clear visual affordance for moving the panel
            HStack {
                // Prominent drag grip (thicker, more obvious)
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Capsule()
                            .fill(.white.opacity(0.85))
                            .frame(width: 20, height: 3)
                    }
                }
                .padding(.leading, 8)
                .accessibilityLabel("Drag to move floating captions")
                .accessibilityHint("Drag this bar to reposition the panel.")

                Spacer()
            }
            .frame(height: 22)
            .background(.black.opacity(0.35))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onPanelDragChanged($0.translation) }
                    .onEnded { _ in onPanelDragEnded() }
            )

            // Top status + controls zone
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Prominent REC indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: isEmphasized ? 10 : 8, height: isEmphasized ? 10 : 8)
                        Text("REC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.red)
                    }
                    .accessibilityLabel("Recording active")

                    Text(presentation.header.captureStatus.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer(minLength: 4)
                }

                FloatingCaptionControlsView(
                    presentation: signalGatePresentation,
                    onActionIntent: onActionIntent
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Transcript zone — comfortable, high contrast, compact
            VStack(alignment: .leading, spacing: 4) {
                ForEach(presentation.lines) { line in
                    FloatingCaptionLineView(
                        line: line,
                        isActive: line.id == presentation.activeLineID
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 45,
                alignment: .bottomLeading
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .background(.regularMaterial)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.mint)
                .frame(width: isEmphasized ? 5 : 3)
                .padding(.vertical, 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEmphasized ? Color.mint.opacity(0.9) : Color.white.opacity(0.15), lineWidth: isEmphasized ? 2 : 1)
                .opacity(isEmphasized ? 0.9 : 0.7)
        }
        .colorScheme(.dark)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isContentSuppressed ? 0 : 1)
        .allowsHitTesting(!isContentSuppressed)
        .accessibilityHidden(isContentSuppressed)
        .transaction { transaction in
            transaction.animation = nil
        }
        .scaleEffect(isEmphasized ? 1.02 : 1.0)
        .opacity(isEmphasized ? 0.97 : 1.0)
        .animation(
            isEmphasized && !reduceMotion ? .easeOut(duration: 0.2) : nil,
            value: isEmphasized
        )
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
        .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.7))
                if isActive {
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.mint)
                }
            }

            Text(line.text)
                .font(isActive ? .body.weight(.medium) : .caption)
                .foregroundStyle(isActive ? Color.mint : .white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = line.translation {
                Text(translation)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
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
