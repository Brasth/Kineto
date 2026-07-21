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
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
        // One-shot entrance only. No continuous animation.
        // Pet receives only non-content state (settled/hidden) per contract.
        let entranceOpacity = state == .hidden ? 0.0 : 1.0
        let entranceOffsetY = state == .hidden ? -8.0 : 0.0
        let settledOffset = (state == .settled && effectiveMotion == .subtle) ? 1.0 : 0.0

        sprite(wave: 0)
            .frame(
                width: visualPreferences.size.points,
                height: visualPreferences.size.points
            )
            .opacity(entranceOpacity)
            .offset(y: entranceOffsetY + settledOffset)
            .animation(
                effectiveMotion == .subtle ? .easeOut(duration: 0.2) : nil,
                value: state
            )
            .contentShape(Rectangle().scale(2.2))
            .allowsHitTesting(state.isPanelDragEligible)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onPanelDragChanged($0.translation) }
                    .onEnded { _ in onPanelDragEnded() }
            )
            .accessibilityHidden(true)
    }
    private func sprite(wave: Double) -> some View {
        let theme = FloatingCaptionPetCatalog.theme(for: visualPreferences.appearance)
        let ds = max(1, displayScale)

        return Canvas { context, size in
            let spriteWidth = CGFloat(theme.sprite.width)
            let spriteHeight = CGFloat(theme.sprite.height)

            let base = min(size.width / spriteWidth, size.height / spriteHeight)
            let pixel = max(2, floor(base * ds) / ds)

            let spriteSize = CGSize(
                width: pixel * spriteWidth,
                height: pixel * spriteHeight
            )

            let origin = CGPoint(
                x: floor((size.width - spriteSize.width) / pixel) * pixel,
                y: floor((size.height - spriteSize.height) / pixel) * pixel
            )

            context.withCGContext { cg in
                cg.interpolationQuality = .none
            }

            // Minimal backing plate for legibility on varied / bright / busy backgrounds
            // (terminal text, light desktops, screen share, etc.). Purely decorative.
            let isHighContrast = colorSchemeContrast == .increased
            let backingPad = isHighContrast ? 2.0 : 1.0
            let backingRect = CGRect(
                x: origin.x - backingPad * pixel,
                y: origin.y - backingPad * pixel,
                width: spriteSize.width + backingPad * 2 * pixel,
                height: spriteSize.height + backingPad * 2 * pixel
            )

            let backingOpacity = colorScheme == .dark
                ? (isHighContrast ? 0.72 : 0.48)
                : (isHighContrast ? 0.38 : 0.26)
            let backingColor = Color.black.opacity(backingOpacity)

            context.fill(Path(backingRect), with: .color(backingColor))

            // Thin border using the existing outline color for cohesion
            let borderOpacity = isHighContrast ? 0.85 : 0.55
            context.stroke(
                Path(roundedRect: backingRect, cornerSize: CGSize(width: pixel * 2, height: pixel * 2)),
                with: .color(outline.opacity(borderOpacity)),
                lineWidth: max(1, pixel * 0.7)
            )
            for y in 0..<theme.sprite.height {
                for x in 0..<theme.sprite.width {
                    guard let baseColor = color(for: theme.sprite[x, y]) else {
                        continue
                    }

                    var dx = origin.x + CGFloat(x) * pixel
                    var dy = origin.y + CGFloat(y) * pixel

                    if theme.sprite[x, y] == .accent || theme.sprite[x, y] == .highlight {
                        dx += wave * 1.2
                        if y >= theme.sprite.height * 2 / 3 {
                            dy += wave * 0.8
                        }
                    }

                    context.fill(
                        Path(CGRect(x: dx, y: dy, width: pixel, height: pixel)),
                        with: .color(baseColor)
                    )
                }
            }
        }
    }

    private func color(for role: FloatingCaptionPetPixelRole) -> Color? {
        switch role {
        case .empty: nil
        case .outline: outline
        case .fill: cream
        case .face: outline
        case .blush: blush
        case .accent: accent
        case .highlight: accent.opacity(0.62)
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
