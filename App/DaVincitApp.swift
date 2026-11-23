import SwiftUI

@main
struct DaVincitApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(Theme.olive)
                .onOpenURL { state.handle(url: $0) }
        }
    }
}
