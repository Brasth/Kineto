import AppKit
import SwiftUI

@main
struct KinetoApp: App {

    @State private var model = AppModel()
    @State private var floatingCaptionPanelCoordinator = FloatingCaptionPanelCoordinator()
    @State private var mainWindowBridge = KinetoMainWindowBridge()
    @Environment(\.openWindow) private var openWindow


    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            HomeView(model: model)
                .frame(minWidth: 360, minHeight: 560)
                .modifier(FloatingCaptionPanelConnectionModifier(
                    model: model,
                    coordinator: floatingCaptionPanelCoordinator,
                    mainWindowBridge: mainWindowBridge
                ))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)

        Settings {
            CompanionSettingsView(model: model)
        }

        MenuBarExtra(
            isInserted: Binding(
                get: { model.signalGatePresentation.isVisible },
                set: { _ in }
            )
        ) {
            SignalGateMenu(
                presentation: model.signalGatePresentation,
                resetCaptionPosition: {
                    floatingCaptionPanelCoordinator.resetCaptionPosition()
                }
            ) { action in
                Task { @MainActor in
                    await performAuthorizedSignalGateAction(
                        action,
                        model: model,
                        mainWindowBridge: mainWindowBridge,
                        openWindow: openWindow
                    )
                }
            }
        } label: {
            SignalGateGlyph(
                phase: model.signalGatePresentation.phase,
                accessibilityValue: model.signalGatePresentation.accessibilityValue
            )
        }
        .menuBarExtraStyle(.menu)
    }

    static let mainWindowID = "kineto-main-window"
}

@MainActor
private final class KinetoMainWindowBridge {
    private weak var window: NSWindow?
    private weak var observedModel: AppModel?
    private var observationGeneration = 0
    private var openWindow: ((String) -> Void)?
    private var hidePanels: () -> Void = {}
    private var openWindowRequestInFlight = false

    func attach(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(KinetoApp.mainWindowID)
        self.window = window
        openWindowRequestInFlight = false
        applyCurrentMode()
    }

    func detach(_ window: NSWindow) {
        guard self.window === window else { return }
        self.window = nil
    }

    func beginObserving(
        _ model: AppModel,
        openWindow: @escaping (String) -> Void,
        hidePanels: @escaping () -> Void
    ) {
        self.openWindow = openWindow
        self.hidePanels = hidePanels
        guard observedModel !== model else {
            applyCurrentMode()
            return
        }
        observedModel = model
        observationGeneration &+= 1
        observe(model, generation: observationGeneration)
    }

    func revealMainWindow(
        for model: AppModel,
        openWindow: OpenWindowAction
    ) {
        self.openWindow = { id in openWindow(id: id) }
        guard model.capturePresentationMode == .mainWindow else { return }
        applyCurrentMode()
    }

    private func observe(_ model: AppModel, generation: Int) {
        let mode = withObservationTracking {
            model.capturePresentationMode
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
        apply(mode)
    }

    private func applyCurrentMode() {
        guard let model = observedModel else { return }
        apply(model.capturePresentationMode)
    }

    private func apply(_ mode: CapturePresentationMode) {
        if mode == .mainWindow {
            hidePanels()
        }

        let windows = identifiedWindows()
        guard !windows.isEmpty else {
            guard mode == .mainWindow, !openWindowRequestInFlight else { return }
            openWindowRequestInFlight = true
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                guard self.identifiedWindows().isEmpty else {
                    self.openWindowRequestInFlight = false
                    return
                }
                self.openWindow?(KinetoApp.mainWindowID)
            }
            return
        }

        openWindowRequestInFlight = false
        switch mode {
        case .mainWindow:
            let window = windows.first(where: { $0 === self.window }) ?? windows[0]
            guard !(window.isVisible && window.isMainWindow && NSApp.isActive) else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        case .floating:
            for window in windows {
                window.orderOut(nil)
            }
        }
    }

    private func identifiedWindows() -> [NSWindow] {
        NSApp.windows.filter {
            $0.identifier?.rawValue == KinetoApp.mainWindowID
        }
    }

}

private struct KinetoMainWindowAccessor: NSViewRepresentable {
    let bridge: KinetoMainWindowBridge

    func makeNSView(context: Context) -> AccessorView {
        AccessorView(bridge: bridge)
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {}

    final class AccessorView: NSView {
        private let bridge: KinetoMainWindowBridge

        init(bridge: KinetoMainWindowBridge) {
            self.bridge = bridge
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let window, window !== newWindow {
                bridge.detach(window)
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                bridge.attach(window)
            }
        }
    }
}

private struct FloatingCaptionPanelConnectionModifier: ViewModifier {
    let model: AppModel
    let coordinator: FloatingCaptionPanelCoordinator
    let mainWindowBridge: KinetoMainWindowBridge

    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .background {
                KinetoMainWindowAccessor(bridge: mainWindowBridge)
                    .frame(width: 0, height: 0)
            }
            .onAppear {
                mainWindowBridge.beginObserving(
                    model,
                    openWindow: { id in openWindow(id: id) },
                    hidePanels: { coordinator.hide() }
                )
                coordinator.beginObserving(model) { action in
                    Task { @MainActor in
                        await performAuthorizedSignalGateAction(
                            action,
                            model: model,
                            mainWindowBridge: mainWindowBridge,
                            openWindow: openWindow
                        )
                    }
                }
            }
    }
}

@MainActor
private func performAuthorizedSignalGateAction(
    _ action: SignalGateAction,
    model: AppModel,
    mainWindowBridge: KinetoMainWindowBridge,
    openWindow: OpenWindowAction
) async {
    guard await model.performSignalGateAction(action) else { return }
    guard action == .showMeetingDetails else { return }
    mainWindowBridge.revealMainWindow(for: model, openWindow: openWindow)
}
