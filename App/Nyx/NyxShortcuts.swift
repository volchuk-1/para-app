import AppIntents

/// Siri and the Action button: «DaVincit Nyx Серце», «DaVincit Nyx стоп». Any of them can also be put on the Action
/// button (Settings → Action Button → Shortcut → DaVincit) or in the Shortcuts app.
struct ParaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NyxPresetIntent(), phrases: [
            "\(.applicationName) Nyx \(\.$preset)",
            "Nyx \(\.$preset) у \(.applicationName)",
        ], shortTitle: "Nyx: пресет", systemImageName: "heart.circle")
        AppShortcut(intent: NyxPlayPauseIntent(), phrases: [
            "\(.applicationName) Nyx пуск",
            "\(.applicationName) Nyx пауза",
        ], shortTitle: "Nyx: пуск/стоп", systemImageName: "playpause.fill")
        AppShortcut(intent: NyxStopIntent(), phrases: [
            "\(.applicationName) Nyx стоп",
            "Зупини Nyx у \(.applicationName)",
        ], shortTitle: "Nyx: стоп", systemImageName: "stop.circle")
    }
}
