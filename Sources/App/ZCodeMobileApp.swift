import SwiftUI

@main
struct ZCodeMobileApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootWorkspaceContainerView(store: store)
                .onAppear { store.startNetworkMonitorIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            store.handleScenePhase(phase)
        }
    }
}
