import SwiftUI

/// Settings in two groups: «Звичайні» (what you change for yourself) and «Системні» (code, keys, server).
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tab = 0
    @State private var name = ""
    @State private var server = KeyStore.serverURL.absoluteString
    @State private var code: String?
    @State private var message: String?
    @State private var confirmSignOut = false
    @State private var scriptKey: String?
    @State private var people = false
    @State private var spot: SpotConnect?
    @State private var remote: RemoteInfo?
    @State private var laptopKey: String?
    @State private var template = "where"
    @State private var mix = false
    @State private var confirmSpotOff = false

    var body: some View {
        NavigationStack {
            SoftForm {
                Section {
                    Picker("Група", selection: $tab) {
                        Text("Звичайні").tag(0)
                        Text("Системні").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if tab == 0 { usual } else { system }
                if let message { Section { Text(message).foregroundStyle(Theme.muted) } }
            }
            .navigationTitle("Налаштування")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .onAppear { name = state.me?.name ?? "" }
            .task {
                spot = try? await API.current().spotifyConnect()
                remote = try? await API.current().remote()
                template = remote?.template ?? "where"
            }
            .sheet(isPresented: $people) { PeopleSheet() }
            .sheet(isPresented: $mix) { MixSheet() }
            .confirmationDialog("Відключити Spotify? Віджет перестане показувати твою музику.", isPresented: $confirmSpotOff, titleVisibility: .visible) {
                Button("Відключити", role: .destructive) { Task { try? await API.current().spotifyOff(); spot = try? await API.current().spotifyConnect() } }
            }
            .confirmationDialog("Вийти? Повернутись можна лише з новим кодом від партнера.", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Вийти", role: .destructive) { state.signOut(); dismiss() }
            }
        }
        .tint(Theme.olive)
    }

    // MARK: Звичайні

    @ViewBuilder private var usual: some View {
        Section {
            TextField("Ім'я", text: $name)
            // only when the name was changed
            if !name.trimmingCharacters(in: .whitespaces).isEmpty && name != state.me?.name {
                Button("Зберегти ім'я") { Task { await rename() } }
            }
        } header: { Text("Твоє ім'я") } footer: {
            Text("Так тебе бачить \(state.partner?.name ?? "партнер") і так тебе називають сповіщення.")
        }
        Section {
            if spot?.ready != true {
                Text("Spotify ще не налаштовано на сервері.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else if spot?.linked != true, let u = spot?.url?.asURL {
                Button { openURL(u) } label: { Label("Підключити мій Spotify", systemImage: "music.note") }
            } else {
                HStack {
                    Label("Підключено", systemImage: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x1DB954))
                    Spacer()
                    Button("Відключити", role: .destructive) { confirmSpotOff = true }.font(.system(size: 14))
                }
                if spot?.mix == true {
                    Button { mix = true } label: { Label("Наш мікс у Spotify", systemImage: "opticaldisc.fill") }
                } else if let u = spot?.url?.asURL {
                    Button { openURL(u) } label: { Label("Оновити доступ (для міксу)", systemImage: "arrow.clockwise") }
                }
            }
        } header: { Text("Spotify") }
        Section {
            Button("Близькі й дні народження") { people = true }
        } footer: { Text("Дні народження — у календарі обох, нагадування за 3 тижні, щоб відкрити збір.") }
    }

    // MARK: Системні

    @ViewBuilder private var system: some View {
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
        Section {
            if let scriptKey {
                Text(scriptKey).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                Button("Скопіювати") { UIPasteboard.general.string = scriptKey; message = "Скопійовано — встав у Scriptable" }
            } else {
                Button("Ключ для віджета") { Task { await newScriptKey() } }
            }
        } header: { Text("Віджет «Витрати»") } footer: {
            Text("Щоб твої витрати й борг ішли в «Мої гроші». Встав ключ у Scriptable: «Витрати» → «🔗 Підключити DaVincit». Бачиш це лише ти; новий ключ вимикає старий.")
        }
        Section {
            if let laptopKey {
                Text(laptopKey).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Button("Скопіювати ключ") { UIPasteboard.general.string = laptopKey; message = "Скопійовано — встав у вікно програми на ноутбуці" }
            } else {
                Button(remote?.connected == true ? "Новий ключ для ноутбука" : "Ключ для ноутбука") {
                    Task { laptopKey = try? await API.current().remoteKey(); remote = try? await API.current().remote() }
                }
            }
            if remote?.connected == true {
                Picker("Де відкривати фільм", selection: Binding(get: { template }, set: { v in template = v; Task { try? await API.current().remoteTemplate(v) } })) {
                    Text("Де дивитись (TMDB)").tag("where")
                    Text("Netflix").tag("netflix")
                    Text("MEGOGO").tag("megogo")
                    Text("Apple TV").tag("appletv")
                    Text("YouTube").tag("youtube")
                    if !["where", "netflix", "megogo", "appletv", "youtube"].contains(template) { Text("Свій сайт").tag(template) }
                }
            }
        } header: { Text("Ноутбук") } footer: {
            Text(laptopNote)
        }
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
        Section {
            Text("Дані про фільми й серіали — TMDB (themoviedb.org). Цей застосунок використовує TMDB API, але не схвалений і не сертифікований TMDB.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text("Спільна папка: \(Shared.groupWorks ? "працює" : "недоступна") (\(Shared.group))")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            Text("Іконка уробороса — Lorc, game-icons.net, ліцензія CC BY 3.0.").font(.system(size: 12)).foregroundStyle(Theme.muted)
        } header: { Text("Про застосунок") }
        Section {
            Button("Вийти з цього телефона", role: .destructive) { confirmSignOut = true }
        }
    }

    private var laptopNote: String {
        guard remote?.connected == true else { return "Щоб кнопка «На ноутбук» на сторінці фільму відкривала його там. Ключ вставляється у вікно програми «DaVincit — ноутбук»; показую один раз." }
        return (remote?.online == true ? "Зараз на зв'язку. " : "Програма на ноутбуці зараз не запущена. ") + "Кнопка «На ноутбук» — на сторінці фільму."
    }

    private func newScriptKey() async {
        do { scriptKey = try await state.api.newScriptKey(); message = nil } catch { message = error.localizedDescription }
    }

    private func rename() async {
        do { state.renamed(try await state.api.rename(name)); message = "Ім'я збережено — тепер ти «\(name)» всюди" }
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
