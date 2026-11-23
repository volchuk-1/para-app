import SwiftUI
import ActivityKit
import WidgetKit
import UserNotifications

/// Probe screen from the SideStore test: App Group + widget, Live Activity. Push probe joins in task 6.
struct DiagnosticsView: View {
    @State private var status = ""
    @State private var note = ""
    @State private var pushResult = ""

    private func probePush() async {
        pushResult = "1/3 Питаю дозвіл на сповіщення…"
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { pushResult = "✗ Сповіщення заборонені в Налаштуваннях iPhone"; return }
            pushResult = "2/3 Реєструюсь в Apple…"
            let token = try await PushProbe.shared.register()
            pushResult = "3/3 ✓ Токен є: \(token.prefix(12))…\nНадсилаю на сервер…"
            let api = API.current()
            try await api.sendPushToken(token)
            let st = try await api.pushStatus()
            pushResult = "✓ iPhone видав токен, сервер його зберіг (токенів: \(st.myTokens)).\n"
                + (st.serverCanSend ? "Сервер уміє надсилати push." : "Щоб сервер надсилав push, потрібен ключ APNs від Apple.")
        } catch {
            let ns = error as NSError
            pushResult = "✗ \(ns.localizedDescription)\n[\(ns.domain) \(ns.code)]"
        }
    }

    var body: some View {
            Form {
                Section {
                    Button("Перевірити push", action: { Task { await probePush() } })
                    if !pushResult.isEmpty {
                        Text(pushResult).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    }
                } header: { Text("Push") } footer: {
                    Text("Покаже, чи дозволяє iPhone цьому застосунку отримувати push. Зроби скрін результату.")
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
            .navigationTitle("Діагностика")
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
