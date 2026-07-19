import SwiftUI

@main
struct KinetoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView(model: model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)
    }
}
