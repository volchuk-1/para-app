import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if state.me != nil && state.isPaired {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .task { await state.refresh() }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await state.refresh() } }
        }
    }
}

/// Wave 1 shell; the tab bar and real screens come in later tasks.
struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            HomeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").foregroundStyle(Theme.cream)
                        }
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}
