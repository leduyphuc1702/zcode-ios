import SwiftUI

@main
struct ZCodeMobileApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootWorkspaceContainerView(store: store)
        }
    }
}
