import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class FloatingCaptionCompanionContent {
    var state: FloatingCaptionPetState = .hidden
    var visualPreferences: FloatingCaptionPetVisualPreferences?
    var onAssetInvalidated: (String) -> Void = { _ in }
    var onPanelDragChanged: (CGSize) -> Void = { _ in }
    var onPanelDragEnded: () -> Void = {}
}

private struct FloatingCaptionCompanionRootView: View {
    @Bindable var content: FloatingCaptionCompanionContent

    var body: some View {
        if let visualPreferences = content.visualPreferences {
            FloatingCaptionPetView(
                state: content.state,
                visualPreferences: visualPreferences,
                onAssetInvalidated: content.onAssetInvalidated,
                onPanelDragChanged: content.onPanelDragChanged,
                onPanelDragEnded: content.onPanelDragEnded
            )
        } else {
            Color.clear
        }
    }
}

@MainActor
final class FloatingCaptionCompanionPanel {
    var onAssetInvalidated: (String) -> Void = { _ in } {
        didSet { content.onAssetInvalidated = onAssetInvalidated }
    }
    var onPanelDragChanged: (CGSize) -> Void = { _ in } {
        didSet { content.onPanelDragChanged = onPanelDragChanged }
    }
    var onPanelDragEnded: () -> Void = {} {
        didSet { content.onPanelDragEnded = onPanelDragEnded }
    }

    private let content: FloatingCaptionCompanionContent
    private let panel: NSPanel
    private let hostingView: NSHostingView<FloatingCaptionCompanionRootView>

    init() {
        let content = FloatingCaptionCompanionContent()
        self.content = content
        hostingView = NSHostingView(
            rootView: FloatingCaptionCompanionRootView(content: content)
        )
        panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: FloatingCaptionPetSize.standard.points,
                height: FloatingCaptionPetSize.standard.points
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        // Crisp pixel art support: nearest-neighbor filtering + disable edge anti-aliasing.
        // This helps the Canvas-drawn 12x12 sprites stay sharp inside the transparent NSPanel.
        hostingView.wantsLayer = true
        if let layer = hostingView.layer {
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.allowsEdgeAntialiasing = false
        }
    }
    func attach(to parent: NSPanel) {
        parent.addChildWindow(panel, ordered: .above)
    }

    func update(
        state: FloatingCaptionPetState,
        visualPreferences: FloatingCaptionPetVisualPreferences
    ) -> CGSize {
        content.state = state
        content.visualPreferences = visualPreferences
        let size = CGSize(
            width: visualPreferences.size.points,
            height: visualPreferences.size.points
        )
        panel.setContentSize(size)
        return size
    }

    var frame: CGRect { panel.frame }

    func setFrameOrigin(_ origin: CGPoint) {
        panel.setFrameOrigin(origin)
    }

    func orderFront() {
        panel.orderFrontRegardless()
    }

    func orderOut() {
        panel.orderOut(nil)
    }
}
