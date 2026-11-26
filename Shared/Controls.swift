import AppIntents
import Foundation

/// The buttons of «Пункт керування» open the app at the right place (iOS 18+).
/// They live in Shared: the widget extension shows them, the app runs them.
@available(iOS 18.0, *)
struct OpenVoiceNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Нотатка голосом"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "davincit://note")!))
    }
}

@available(iOS 18.0, *)
struct OpenMomentIntent: AppIntent {
    static var title: LocalizedStringResource = "Миттєвість"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "davincit://snap")!))
    }
}
