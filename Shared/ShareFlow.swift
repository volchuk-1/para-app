import SwiftUI
import UIKit

/// What happens after «Поділитися → DaVincit»: the server decides watch vs wish; we show the result.
struct ShareFlowView: View {
    let url: URL
    var onDone: () -> Void

    enum Phase {
        case loading
        case watch(caption: String?, candidates: [Candidate])
        case added(String)
        case wish(Wish)
        case failed(String)
        case noKey
        case offline
    }
    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var busy = false
    @State private var copied = false
    private var me: Member? { KeyStore.cachedMe?.me }
    private var partner: Member? { KeyStore.cachedMe?.partner }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                (Text("Da") + Text("Vi").italic() + Text("ncit")).font(.serif(22))
                Spacer()
                Button("Готово", action: onDone).font(.system(size: 16, weight: .semibold))
            }
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .tint(Theme.olive)
        .task { await start() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 10) { ProgressView(); Text("Розпізнаю…") }.padding(.top, 20)
        case .failed(let msg):
            Text(msg).font(.system(size: 16)).padding(.top, 10)
        case .offline:
            VStack(alignment: .leading, spacing: 12) {
                Text("Немає зв'язку з сервером.").font(.system(size: 16, weight: .semibold))
                Button("Спробувати ще раз") { phase = .loading; Task { await start() } }
                    .buttonStyle(PillButtonStyle(fill: Theme.olive, text: Theme.cream))
            }
        case .noKey:
            VStack(alignment: .leading, spacing: 12) {
                Text("Це вікно не бачить вашої пари.").font(.system(size: 16, weight: .semibold))
                Text("Так буває, якщо SideStore не дав спільної папки. Скопіюй посилання, відкрий DaVincit → «+» → «Бажання» або «Фільм / серіал» і встав його.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                Button { UIPasteboard.general.url = url; copied = true } label: {
                    Label(copied ? "Скопійовано ✓" : "Скопіювати посилання", systemImage: "doc.on.doc")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.olive, text: Theme.cream))
            }
        case .added(let title):
            VStack(alignment: .leading, spacing: 8) {
                Label("Додано у «Дивимось»", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.olive)
                    .font(.system(size: 17, weight: .semibold))
                Text(title).font(.serif(26, .bold))
            }
        case .wish(let w):
            VStack(alignment: .leading, spacing: 10) {
                Label("Додано в бажання", systemImage: "gift.fill").foregroundStyle(Theme.olive)
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 12) {
                    RemoteImage(url: w.imageUrl, contentMode: .fit).frame(width: 70, height: 70)
                        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(w.title).font(.system(size: 16, weight: .semibold)).lineLimit(3)
                        if let p = w.priceText { Text(p).font(.system(size: 15)) }
                    }
                }
                if let me, let partner {
                    Picker("Чиє", selection: Binding(get: { w.ownerId }, set: { id in Task { await setOwner(w, id) } })) {
                        Text("Моє").tag(me.id)
                        Text(partner.name).tag(partner.id)
                    }
                    .pickerStyle(.segmented)
                }
            }
        case .watch(let caption, let candidates):
            VStack(alignment: .leading, spacing: 10) {
                Text(candidates.isEmpty ? "Не вгадав назву. Впиши її:" : "Що це? Торкнись правильне:")
                    .font(.system(size: 16, weight: .semibold))
                if let caption { Text(caption).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(3) }
                ForEach(candidates) { c in
                    Button { Task { await add(c) } } label: { CandidateRow(c: c) }.disabled(busy)
                }
                HStack {
                    TextField("Назва фільму чи серіалу", text: $query).field()
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: { Image(systemName: "magnifyingglass").frame(width: 50, height: 54) }
                }
            }
        }
    }

    private func start() async {
        guard KeyStore.deviceKey != nil else { phase = .noKey; return }
        do {
            let r = try await API.current().share(url)
            if r.kind == "wish", let w = r.wish { phase = .wish(w) }
            else { phase = .watch(caption: r.caption, candidates: r.candidates ?? []) }
        } catch APIError.offline {
            phase = .offline
        } catch APIError.unauthorized {
            phase = .noKey
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func add(_ c: Candidate) async {
        busy = true; defer { busy = false }
        do {
            let w = try await API.current().addWatch(c, sourceUrl: url.absoluteString)
            phase = .added(w.title)
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true; defer { busy = false }
        let caption: String? = { if case .watch(let c, _) = phase { return c } else { return nil } }()
        do { phase = .watch(caption: caption, candidates: try await API.current().search(query)) }
        catch { phase = .failed(error.localizedDescription) }
    }

    private func setOwner(_ w: Wish, _ id: String) async {
        do { phase = .wish(try await API.current().patchWish(w.id, .init(ownerId: id))) }
        catch { phase = .failed(error.localizedDescription) }
    }
}

struct CandidateRow: View {
    let c: Candidate
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: c.posterUrl).frame(width: 52, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text([c.isAnime ? "Аніме" : (c.mediaType == "tv" ? "Серіал" : "Фільм"), c.year.map(String.init), c.originalTitle]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer()
            Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Theme.olive)
        }
        .padding(.vertical, 4)
    }
}
