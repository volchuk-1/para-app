import SwiftUI
import UIKit

@main
struct DaVincitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    init() { Theme.applyAppearance(); NyxManager.install() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .tint(Theme.olive)
                .preferredColorScheme(state.whiteStatusBar ? .dark : .light)
                .onOpenURL { state.handle(url: $0) }
        }
    }
}

/// Receives the APNs registration result for the push probe.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushProbe.shared.finish(.success(token))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushProbe.shared.finish(.failure(error))
    }
}

/// Bridges the delegate callback to an async call.
@MainActor
final class PushProbe {
    static let shared = PushProbe()
    private var waiter: CheckedContinuation<String, Error>?

    nonisolated func finish(_ result: Result<String, Error>) {
        Task { @MainActor in
            self.waiter?.resume(with: result)
            self.waiter = nil
        }
    }

    /// Asks iOS for a push token; throws Apple's error if the app is not allowed to get one.
    func register() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            waiter?.resume(throwing: CancellationError())
            waiter = c
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
