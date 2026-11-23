import SwiftUI
import ActivityKit
import WidgetKit

@main
struct ParaApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var status = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Проба") {
                    Text("Якщо ти це бачиш, застосунок встановився через SideStore.")
                }
                Section("Віджет і спільна папка") {
                    TextField("Текст для віджета", text: $note)
                    Button("Зберегти для віджета", action: save)
                }
                Section("Dynamic Island") {
                    Button("Почати відлік 10 хвилин", action: start)
                    Button("Зупинити", role: .destructive, action: stop)
                }
                if !status.isEmpty {
                    Section("Результат") { Text(status) }
                }
            }
            .navigationTitle("Двоє · проба")
        }
    }

    private func save() {
        guard let defaults = UserDefaults(suiteName: Shared.group) else {
            status = "✗ Спільна папка (App Group) недоступна"
            return
        }
        defaults.set(note.isEmpty ? "привіт" : note, forKey: "note")
        WidgetCenter.shared.reloadAllTimelines()
        status = "✓ Збережено. Додай віджет «Двоє» на головний екран і подивись, чи він бачить цей текст."
    }

    private func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "✗ Live Activities вимкнені: Налаштування → Двоє → Live Activities"
            return
        }
        let state = PingAttributes.ContentState(endsAt: Date().addingTimeInterval(600), label: "Побачення")
        do {
            _ = try Activity.request(attributes: PingAttributes(title: "Проба"),
                                     content: .init(state: state, staleDate: nil))
            status = "✓ Відлік запущено. Заблокуй екран або вийди на головний: має бути в Dynamic Island."
        } catch {
            status = "✗ Live Activity: \(error.localizedDescription)"
        }
    }

    private func stop() {
        Task {
            for activity in Activity<PingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            status = "Зупинено"
        }
    }
}
