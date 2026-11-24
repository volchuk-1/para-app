import SwiftUI

/// «Наш мікс»: a private Spotify playlist from the songs each of us plays most — in turns, mine, yours, mine…
/// It is collaborative, so both can add songs. Built on the server from each one's top songs.
struct MixSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var info: MixInfo?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        let pn = state.partner?.name ?? "партнер"
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Наш мікс").font(.serif(30, .bold))
                Text("Плейлист у Spotify з пісень, які ви обоє слухаєте найбільше — по черзі: твоя, \(pn), твоя… Він спільний: додавати пісні можете обоє.")
                    .font(.system(size: 14.5)).foregroundStyle(Theme.muted)
                if let p = info?.partner, !p.mix {
                    Text("\(pn) ще не підключила Spotify\(p.linked ? " з новим доступом" : "") — поки мікс лише з твоїх пісень.")
                        .font(.system(size: 13.5)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.tan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if let m = info?.mix {
                    Text("\(m.count) пісень · оновлено \(m.updatedAt.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))))")
                        .font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                    if let u = m.url?.asURL {
                        Button { openURL(u) } label: { wide("Відкрити в Spotify", "play.circle.fill", filled: true) }
                    }
                }
                if let error { Text(error).font(.system(size: 13.5)).foregroundStyle(Theme.coffee) }
                Button { Task { await build() } } label: {
                    wide(busy ? "Збираю…" : info?.mix == nil ? "Зібрати наш мікс" : "Оновити мікс", "arrow.clockwise", filled: info?.mix == nil)
                }
                .disabled(busy)
            }
            .padding(20)
        }
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium, .large])
        .task { info = try? await API.current().spotifyMix() }
    }

    private func wide(_ t: String, _ icon: String, filled: Bool) -> some View {
        Label(t, systemImage: icon).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
            .background(filled ? Theme.olive : Theme.tan, in: Capsule())
            .foregroundStyle(filled ? Theme.cream : Theme.ink)
    }

    private func build() async {
        busy = true; defer { busy = false }
        do {
            _ = try await API.current().buildMix()
            Haptic.ok(); error = nil
            info = try? await API.current().spotifyMix()
        } catch APIError.other(let code) {
            error = ["SPOTIFY_RECONNECT": "Онови доступ Spotify у налаштуваннях — для міксу потрібен новий дозвіл.",
                     "SPOTIFY_FORBIDDEN": "Spotify не дозволив. Перевір, що ти доданий у User Management застосунку Spotify, а власник застосунку має Premium.",
                     "SPOTIFY_EMPTY": "Spotify ще не знає твоїх улюблених пісень — послухай трохи й спробуй пізніше.",
                     "SPOTIFY_OFF": "Spotify ще не налаштовано на сервері."][code] ?? "Не вийшло: \(code)"
        } catch {
            self.error = error.localizedDescription
        }
    }
}
