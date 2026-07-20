import AppKit

struct FloatingCaptionPanelPlacement: Equatable {
    static let defaultsKey = "kineto.floatingCaption.panelPlacement.v1"

    let horizontal: CGFloat
    let vertical: CGFloat

    init?(horizontal: CGFloat, vertical: CGFloat) {
        guard
            horizontal.isFinite,
            vertical.isFinite,
            (0...1).contains(horizontal),
            (0...1).contains(vertical)
        else {
            return nil
        }
        self.horizontal = horizontal
        self.vertical = vertical
    }

    static func restore(for displayID: CGDirectDisplayID, defaults: UserDefaults) -> Self? {
        guard
            let values = defaults.dictionary(forKey: defaultsKey)?[String(displayID)] as? [String: Any],
            let horizontal = values["horizontal"] as? NSNumber,
            let vertical = values["vertical"] as? NSNumber
        else {
            return nil
        }
        return Self(horizontal: horizontal.doubleValue, vertical: vertical.doubleValue)
    }

    func persist(for displayID: CGDirectDisplayID, defaults: UserDefaults) {
        var placements = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        placements[String(displayID)] = [
            "horizontal": Double(horizontal),
            "vertical": Double(vertical)
        ]
        defaults.set(placements, forKey: Self.defaultsKey)
    }

    static func fallback(visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        clamp(
            origin: CGPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.minY + 40
            ),
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )
    }

    static func linkedSize(
        captionSize: CGSize,
        companionSize: CGSize,
        verticalGap: CGFloat
    ) -> CGSize {
        guard companionSize != .zero else { return captionSize }
        return CGSize(
            width: max(captionSize.width, companionSize.width),
            height: captionSize.height + verticalGap + companionSize.height
        )
    }

    static func companionOrigin(
        captionFrame: CGRect,
        companionSize: CGSize,
        verticalGap: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: captionFrame.midX - companionSize.width / 2,
            y: captionFrame.maxY + verticalGap
        )
    }

    static func captionOrigin(
        companionOrigin: CGPoint,
        captionSize: CGSize,
        companionSize: CGSize,
        verticalGap: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: companionOrigin.x - (captionSize.width - companionSize.width) / 2,
            y: companionOrigin.y - captionSize.height - verticalGap
        )
    }

    static func placement(for origin: CGPoint, visibleFrame: CGRect, panelSize: CGSize) -> Self {
        let clamped = clamp(origin: origin, visibleFrame: visibleFrame, panelSize: panelSize)
        let horizontalRange = max(visibleFrame.width - panelSize.width, 0)
        let verticalRange = max(visibleFrame.height - panelSize.height, 0)
        return Self(
            horizontal: horizontalRange > 0
                ? (clamped.x - visibleFrame.minX) / horizontalRange
                : 0.5,
            vertical: verticalRange > 0
                ? (clamped.y - visibleFrame.minY) / verticalRange
                : 0
        )!
    }

    func origin(visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        Self.clamp(
            origin: CGPoint(
                x: visibleFrame.minX + horizontal * max(visibleFrame.width - panelSize.width, 0),
                y: visibleFrame.minY + vertical * max(visibleFrame.height - panelSize.height, 0)
            ),
            visibleFrame: visibleFrame,
            panelSize: panelSize
        )
    }

    static func clamp(origin: CGPoint, visibleFrame: CGRect, panelSize: CGSize) -> CGPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }
}
