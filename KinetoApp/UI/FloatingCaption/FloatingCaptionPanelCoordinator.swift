import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor
final class FloatingCaptionPanelCoordinator {
    private let panel: NSPanel
    private let hostingView: NSHostingView<FloatingCaptionView>
    private let companionPanel: FloatingCaptionCompanionPanel
    private let dragSession = FloatingCaptionDragSession()
    private var pendingPresentation: FloatingCaptionOverlayPresentation?
    private var displayedPresentation: FloatingCaptionOverlayPresentation?
    private var deliveryTask: Task<Void, Never>?
    private var lastDeliveryDate: Date?
    private var captionDragStartOrigin: CGPoint?
    private var companionDragStartOrigin: CGPoint?
    private var presentationDeferredForDrag = false
    private var companionSize = CGSize.zero
    private weak var observedModel: AppModel?
    private var performAction: (SignalGateAction) -> Void = { _ in }
    private var observationGeneration = 0

    init() {
        hostingView = NSHostingView(rootView: FloatingCaptionView(
            presentation: .hidden,
            width: Self.defaultWidth
        ))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        companionPanel = FloatingCaptionCompanionPanel()
        companionPanel.onPanelDragChanged = { [weak self] in self?.updateCompanionDrag($0) }
        companionPanel.onPanelDragEnded = { [weak self] in self?.endPanelDrag(.companion) }
        companionPanel.attach(to: panel)
    }

    deinit { deliveryTask?.cancel() }

    func beginObserving(
        _ model: AppModel,
        performAction: @escaping (SignalGateAction) -> Void
    ) {
        self.performAction = performAction
        guard observedModel !== model else { return }
        observedModel = model
        observationGeneration &+= 1
        observe(model, generation: observationGeneration)
    }
    private func handleActionIntent(_ action: SignalGateAction) {
        if action == .pauseOrResume || action == .stop {
            hide()
        }
        performAction(action)
    }


    private func observe(_ model: AppModel, generation: Int) {
        let observedState = withObservationTracking {
            (
                model.capturePresentationMode,
                model.floatingCaptionOverlayPresentation
            )
        } onChange: { [weak self, weak model] in
            Task { @MainActor [weak self, weak model] in
                guard
                    let self,
                    let model,
                    self.observedModel === model,
                    self.observationGeneration == generation
                else {
                    return
                }
                self.observe(model, generation: generation)
            }
        }
        let presentation = observedState.0 == .floating
            ? observedState.1
            : .hidden
        present(presentation)
    }

    func present(_ presentation: FloatingCaptionOverlayPresentation) {
        guard presentation.isVisible else {
            hide()
            return
        }
        pendingPresentation = presentation
        guard deliveryTask == nil else { return }

        let elapsed = lastDeliveryDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0, Self.minimumDeliveryInterval - elapsed)
        guard delay > 0 else {
            deliverPendingPresentation()
            return
        }
        deliveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.deliveryTask = nil
            self.deliverPendingPresentation()
        }
    }

    func hide() {
        pendingPresentation = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        dragSession.reset()
        displayedPresentation = nil
        captionDragStartOrigin = nil
        companionDragStartOrigin = nil
        presentationDeferredForDrag = false
        companionSize = .zero
        companionPanel.orderOut()
        hostingView.rootView = rootView(for: .hidden, width: captionWidth(for: displayScreen()))
        panel.orderOut(nil)
    }

    private func deliverPendingPresentation() {
        guard !dragSession.isActive else {
            presentationDeferredForDrag = true
            return
        }
        guard let presentation = pendingPresentation else { return }
        pendingPresentation = nil
        lastDeliveryDate = Date()

        let screen = displayScreen()
        hostingView.rootView = rootView(
            for: presentation,
            width: captionWidth(for: screen)
        )
        panel.setContentSize(hostingView.fittingSize)

        if presentation.caption.petState == .hidden {
            companionSize = .zero
            companionPanel.orderOut()
        } else {
            companionSize = companionPanel.update(
                state: presentation.caption.petState,
                visualPreferences: presentation.petVisualPreferences
            )
        }

        if let screen {
            positionPanels(on: screen)
        }
        panel.orderFrontRegardless()
        if companionSize != .zero {
            companionPanel.orderFront()
        }
        displayedPresentation = presentation
    }

    private func rootView(
        for presentation: FloatingCaptionOverlayPresentation,
        width: CGFloat
    ) -> FloatingCaptionView {
        FloatingCaptionView(
            presentation: presentation.caption,
            width: width,
            signalGatePresentation: presentation.signalGatePresentation,
            isContentSuppressed: dragSession.shouldSuppressCaption,
            onPanelDragChanged: { [weak self] in self?.updateCaptionDrag($0) },
            onPanelDragEnded: { [weak self] in self?.endPanelDrag(.captionHeader) },
            onActionIntent: { [weak self] in self?.handleActionIntent($0) }
        )
    }

    private func updateCaptionDrag(_ translation: CGSize) {
        dragSession.begin(.captionHeader)
        guard dragSession.source == .captionHeader else { return }
        if captionDragStartOrigin == nil {
            captionDragStartOrigin = panel.frame.origin
        }
        let start = captionDragStartOrigin ?? panel.frame.origin
        moveCaption(
            to: CGPoint(
                x: start.x + translation.width,
                y: start.y - translation.height
            )
        )
    }

    private func updateCompanionDrag(_ translation: CGSize) {
        guard companionSize != .zero else { return }
        let wasSuppressingCaption = dragSession.shouldSuppressCaption
        dragSession.begin(.companion)
        guard dragSession.source == .companion else { return }
        if !wasSuppressingCaption {
            replaceCaptionRootView()
        }
        if companionDragStartOrigin == nil {
            companionDragStartOrigin = companionPanel.frame.origin
        }
        let start = companionDragStartOrigin ?? companionPanel.frame.origin
        let companionOrigin = CGPoint(
            x: start.x + translation.width,
            y: start.y - translation.height
        )
        moveCaption(
            to: FloatingCaptionPanelPlacement.captionOrigin(
                companionOrigin: companionOrigin,
                captionSize: panel.frame.size,
                companionSize: companionSize,
                verticalGap: Self.companionGap
            )
        )
    }

    private func moveCaption(to proposedOrigin: CGPoint) {
        guard let screen = screen(for: linkedFrame(origin: proposedOrigin)) ?? displayScreen() else {
            return
        }
        panel.setFrameOrigin(FloatingCaptionPanelPlacement.clamp(
            origin: proposedOrigin,
            visibleFrame: screen.visibleFrame,
            panelSize: linkedPanelSize
        ))
        synchronizeCompanionPosition()
    }

    private func endPanelDrag(_ source: FloatingCaptionDragSource) {
        guard dragSession.source == source else { return }
        dragSession.end()
        captionDragStartOrigin = nil
        companionDragStartOrigin = nil
        if let screen = screen(for: linkedFrame(origin: panel.frame.origin)) ?? displayScreen(),
           let displayID = displayID(for: screen)
        {
            FloatingCaptionPanelPlacement.placement(
                for: panel.frame.origin,
                visibleFrame: screen.visibleFrame,
                panelSize: panel.frame.size
            ).persist(for: displayID, defaults: .standard)
        }
        if presentationDeferredForDrag {
            presentationDeferredForDrag = false
            deliverPendingPresentation()
        } else {
            replaceCaptionRootView()
        }
    }

    private func replaceCaptionRootView() {
        guard let displayedPresentation else { return }
        hostingView.rootView = rootView(
            for: displayedPresentation,
            width: panel.frame.width
        )
    }

    func resetCaptionPosition() {
        guard let screen = displayScreen() else { return }
        if let displayID = displayID(for: screen) {
            var placements = UserDefaults.standard.dictionary(
                forKey: FloatingCaptionPanelPlacement.defaultsKey
            ) ?? [:]
            placements.removeValue(forKey: String(displayID))
            UserDefaults.standard.set(placements, forKey: FloatingCaptionPanelPlacement.defaultsKey)
        }
        panel.setContentSize(hostingView.fittingSize)
        let fallback = FloatingCaptionPanelPlacement.fallback(
            visibleFrame: screen.visibleFrame,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(constrainedCaptionOrigin(fallback, on: screen))
        synchronizeCompanionPosition()
    }

    private var linkedPanelSize: CGSize {
        FloatingCaptionPanelPlacement.linkedSize(
            captionSize: panel.frame.size,
            companionSize: companionSize,
            verticalGap: Self.companionGap
        )
    }

    private func linkedFrame(origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: linkedPanelSize)
    }

    private func positionPanels(on screen: NSScreen) {
        let placement = displayID(for: screen).flatMap {
            FloatingCaptionPanelPlacement.restore(for: $0, defaults: .standard)
        }
        let origin = placement?.origin(
            visibleFrame: screen.visibleFrame,
            panelSize: panel.frame.size
        ) ?? FloatingCaptionPanelPlacement.fallback(
            visibleFrame: screen.visibleFrame,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(constrainedCaptionOrigin(origin, on: screen))
        synchronizeCompanionPosition()
    }

    private func constrainedCaptionOrigin(_ origin: CGPoint, on screen: NSScreen) -> CGPoint {
        FloatingCaptionPanelPlacement.clamp(
            origin: origin,
            visibleFrame: screen.visibleFrame,
            panelSize: linkedPanelSize
        )
    }

    private func synchronizeCompanionPosition() {
        guard companionSize != .zero else { return }
        companionPanel.setFrameOrigin(FloatingCaptionPanelPlacement.companionOrigin(
            captionFrame: panel.frame,
            companionSize: companionSize,
            verticalGap: Self.companionGap
        ))
    }

    private func displayScreen() -> NSScreen? {
        screen(for: panel.frame)
            ?? panel.screen
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(center) }) {
            return screen
        }
        return NSScreen.screens.max {
            let lhs = $0.visibleFrame.intersection(frame)
            let rhs = $1.visibleFrame.intersection(frame)
            return lhs.width * lhs.height < rhs.width * rhs.height
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private func captionWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.defaultWidth }
        return min(Self.defaultWidth, max(Self.minimumWidth, screen.visibleFrame.width - 48))
    }

    private static let defaultWidth: CGFloat = 576
    private static let minimumWidth: CGFloat = 320
    private static let companionGap: CGFloat = 8
    private static let minimumDeliveryInterval: TimeInterval = 0.25
}
