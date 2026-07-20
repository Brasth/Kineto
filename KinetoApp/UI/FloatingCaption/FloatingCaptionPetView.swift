import SwiftUI

extension FloatingCaptionPetState {
    var isPanelDragEligible: Bool {
        self != .hidden
    }
}


struct FloatingCaptionPetView: View {
    let state: FloatingCaptionPetState
    let visualPreferences: FloatingCaptionPetVisualPreferences
    let onPanelDragChanged: (CGSize) -> Void
    let onPanelDragEnded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        state: FloatingCaptionPetState,
        visualPreferences: FloatingCaptionPetVisualPreferences,
        onPanelDragChanged: @escaping (CGSize) -> Void = { _ in },
        onPanelDragEnded: @escaping () -> Void = {}
    ) {
        self.state = state
        self.visualPreferences = visualPreferences
        self.onPanelDragChanged = onPanelDragChanged
        self.onPanelDragEnded = onPanelDragEnded
    }

    var body: some View {
        sprite
            .frame(
                width: visualPreferences.size.points,
                height: visualPreferences.size.points
            )
            .opacity(state == .hidden ? 0 : state == .settled ? 0.86 : 1)
            .offset(y: state == .settled ? 1 : 0)
            .animation(
                effectiveMotion == .subtle ? .easeOut(duration: 0.18) : nil,
                value: state
            )
            .allowsHitTesting(state.isPanelDragEligible)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onPanelDragChanged($0.translation) }
                    .onEnded { _ in onPanelDragEnded() }
            )
            .accessibilityHidden(true)
    }

    private var sprite: some View {
        let theme = FloatingCaptionPetCatalog.theme(for: visualPreferences.appearance)

        return Canvas { context, size in
            let spriteWidth = CGFloat(theme.sprite.width)
            let spriteHeight = CGFloat(theme.sprite.height)
            let pixel = max(2, floor(min(size.width / spriteWidth, size.height / spriteHeight)))
            let spriteSize = CGSize(
                width: pixel * spriteWidth,
                height: pixel * spriteHeight
            )
            let origin = CGPoint(
                x: floor((size.width - spriteSize.width) / 2),
                y: floor((size.height - spriteSize.height) / 2)
            )

            for y in 0..<theme.sprite.height {
                for x in 0..<theme.sprite.width {
                    guard let color = color(for: theme.sprite[x, y]) else {
                        continue
                    }

                    context.fill(
                        Path(
                            CGRect(
                                x: origin.x + CGFloat(x) * pixel,
                                y: origin.y + CGFloat(y) * pixel,
                                width: pixel,
                                height: pixel
                            )
                        ),
                        with: .color(color)
                    )
                }
            }
        }
    }

    private func color(for role: FloatingCaptionPetPixelRole) -> Color? {
        switch role {
        case .empty:
            nil
        case .outline:
            outline
        case .fill:
            cream
        case .face:
            outline
        case .blush:
            blush
        case .accent:
            accent
        case .highlight:
            accent.opacity(0.62)
        }
    }

    private var outline: Color { Color(red: 0.24, green: 0.19, blue: 0.12) }
    private var cream: Color { Color(red: 0.98, green: 0.91, blue: 0.76) }
    private var blush: Color { Color(red: 0.94, green: 0.52, blue: 0.48) }
    private var stem: Color { Color(red: 0.43, green: 0.30, blue: 0.12) }
    private var accent: Color { Color(cgColor: visualPreferences.accent.cgColor) }

    private var effectiveMotion: FloatingCaptionPetMotion {
        visualPreferences.motion.effective(reduceMotion: reduceMotion)
    }
}
