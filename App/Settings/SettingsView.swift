import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var server = KeyStore.serverURL.absoluteString
    @State private var code: PairCode?
    @State private var message: String?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ти") {
                    TextField("Ім'я", text: $name)
                    Button("Зберегти ім'я") { Task { await rename() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == state.me?.name)
                }
                Section {
                    if let p = state.partner {
                        Button("Новий код для телефона: \(p.name)") { Task { await newCode(for: p) } }
                    }
                    if let me = state.me {
                        Button("Новий код для мого іншого телефона") { Task { await newCode(for: me) } }
                    }
                    if let code {
                        Text(code.pairCode)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .textSelection(.enabled)
                        ShareLink(item: "Код для DaVincit: \(code.pairCode)")
                    }
                } header: { Text("Пристрої") } footer: { Text("Код діє 24 години і спрацює один раз.") }
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

    private func newCode(for m: Member) async {
        do { code = try await state.api.deviceCode(for: m.id); message = nil }
        catch { message = error.localizedDescription }
    }
}
