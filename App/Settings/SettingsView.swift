import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var server = KeyStore.serverURL.absoluteString
    @State private var code: String?
    @State private var message: String?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            SoftForm {
                Section("Ти") {
                    TextField("Ім'я", text: $name)
                    Button("Зберегти ім'я") { Task { await rename() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == state.me?.name)
                }
                Section {
                    if let code {
                        Text(code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        ShareLink(item: "Код пари в DaVincit: \(code)")
                        Button("Змінити код (старий перестане працювати)", role: .destructive) { Task { await renew() } }
                    } else {
                        Button("Показати код пари") { Task { await loadCode() } }
                    }
                } header: { Text("Код пари") } footer: { Text("Для вас обох і для будь-якого пристрою: «У мене є код» → обрати себе.") }
                Section("Сповіщення") {
                    NavigationLink("Перевірити push і віджети") { DiagnosticsView() }
                }
                Section("Сервер") {
                    TextField("Адреса", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Зберегти адресу") {
                        if let u = URL(string: server), u.scheme?.hasPrefix("http") == true { KeyStore.serverURL = u; message = "Збережено" }
                        else { message = "Неправильна адреса" }
                    }
                }
                if let message { Section { Text(message).foregroundStyle(Theme.muted) } }
                Section {
                    Text("Дані про фільми й серіали — TMDB (themoviedb.org). Цей застосунок використовує TMDB API, але не схвалений і не сертифікований TMDB.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Text("Спільна папка: \(Shared.groupWorks ? "працює" : "недоступна") (\(Shared.group))")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                } header: { Text("Про застосунок") }
                Section {
                    Button("Вийти з цього телефона", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Налаштування")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .onAppear { name = state.me?.name ?? "" }
            .confirmationDialog("Вийти? Повернутись можна лише з новим кодом від партнера.", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Вийти", role: .destructive) { state.signOut(); dismiss() }
            }
        }
    }

    private func rename() async {
        do { state.renamed(try await state.api.rename(name)); message = "Ім'я збережено" }
        catch { message = error.localizedDescription }
    }

    private func loadCode() async {
        do { code = try await state.api.coupleCode(); message = nil }
        catch { message = error.localizedDescription }
    }

    private func renew() async {
        do { code = try await state.api.newCoupleCode(); message = "Новий код створено" }
        catch { message = error.localizedDescription }
    }
}
