import SwiftUI
import VisionKit
import PhotosUI

/// Наші полиці: spines on a wooden shelf; a tapped book slides out and turns to its cover.
struct BooksPage: View {
    @EnvironmentObject var state: AppState
    @State private var books: [Book] = []
    @State private var mine = true
    @State private var open: Book?
    @State private var add: AddMode?
    @State private var error: String?

    enum AddMode: String, Identifiable { case scan, manual; var id: String { rawValue } }

    private var owner: String? { mine ? state.me?.id : state.partner?.id }
    private var list: [Book] { books.filter { $0.ownerId == owner } }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PageTitle(plain: "Наші", italic: "полиці", sub: "Тап по корінцю — книга виїжджає")
                    Picker("", selection: $mine) {
                        Text("Моя полиця").tag(true)
                        Text("Полиця · \(state.partner?.name ?? "")").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if list.isEmpty {
                        EmptyCard(text: "Полиця порожня. Відскануй штрихкод на звороті книжки або додай вручну.")
                    } else {
                        shelf
                    }
                    HStack(spacing: 8) {
                        addButton("Штрихкод", "barcode.viewfinder") { add = .scan }
                        addButton("Вручну", "pencil") { add = .manual }
                    }
                    section("Читаю", list.filter { $0.status == .reading || $0.status == .paused })
                    section("Хочу прочитати", list.filter { $0.status == .want })
                    section("Прочитано", list.filter { $0.status == .done })
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 120)
            }
            .background(Theme.cream.ignoresSafeArea())
            if let b = open {
                BookPullOut(book: b, onClose: { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { open = nil } }, onChange: { nb in
                    if let nb { books = books.map { $0.id == nb.id ? nb : $0 }; open = nb } else { books.removeAll { $0.id == b.id }; open = nil }
                })
                .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .sheet(item: $add) { m in
            AddBookSheet(mode: m) { b in books.insert(b, at: 0); mine = b.ownerId == state.me?.id }
        }
    }

    private var shelf: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(hex: 0xB08A66), Color(hex: 0x8A6748)], startPoint: .top, endPoint: .bottom))
                .frame(height: 16).shadow(color: Color(hex: 0x3C2814).opacity(0.25), radius: 8, y: 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(list) { b in
                        Button { withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { open = b } } label: { Spine(book: b) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 16)
            }
        }
        .frame(height: 230)
    }

    private func addButton(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private func section(_ title: String, _ items: [Book]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 19, weight: .semibold)).padding(.top, 6)
            ForEach(items) { b in
                Button { withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { open = b } } label: {
                    HStack(spacing: 12) {
                        BookCover(book: b).frame(width: 44, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(2)
                            Text([b.author, b.status.label, b.currentPage.map { "стор. \($0)" + (b.pages.map { " з \($0)" } ?? "") }].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            if b.status == .reading || b.status == .paused, b.pages != nil {
                                ProgressView(value: b.progress).tint(Theme.coffee)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        do { books = try await API.current().books(); error = nil } catch { self.error = error.localizedDescription }
    }
}

enum BookLook {
    static let colors: [UInt32] = [0x3E5568, 0x7A6A55, 0x2E2B27, 0x8C5E3C, 0xC9B58F, 0xB8473A, 0x4B5E3A, 0xE2C7A7, 0x5E5C50, 0xA8763E]
    static func hex(_ b: Book) -> UInt32 { colors[b.title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count] }
    static func color(_ b: Book) -> Color { Color(hex: hex(b)) }
    static func light(_ b: Book) -> Bool { [0xC9B58F, 0xE2C7A7].contains(hex(b)) }
}

struct Spine: View {
    let book: Book
    var body: some View {
        ZStack(alignment: .top) {
            BookLook.color(book)
            Text(book.title).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
                .fixedSize().rotationEffect(.degrees(-90)).frame(width: 34).frame(maxHeight: .infinity)
                .foregroundStyle(BookLook.light(book) ? Theme.ink : Theme.cream)
            if book.status == .reading { Circle().fill(Theme.paper).frame(width: 8, height: 8).padding(.top, 8) }
        }
        .frame(width: 34, height: CGFloat(150 + (book.pages ?? 200) % 60))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 2)
        .rotationEffect(.degrees(book.status == .paused ? -7 : 0), anchor: .bottom)
    }
}

struct BookCover: View {
    let book: Book
    var body: some View {
        ZStack {
            LinearGradient(colors: [BookLook.color(book), BookLook.color(book).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let u = book.coverUrl {
                if u.contains("/files/") { AuthImage(url: u) } else { RemoteImage(url: u) }
            } else {
                VStack(alignment: .leading) {
                    Text(book.author ?? "").font(.system(size: 9, weight: .semibold)).textCase(.uppercase).opacity(0.85)
                    Spacer()
                    Text(book.title).font(.serif(15, .bold)).lineLimit(4)
                    Spacer()
                    Text("DaVincit").font(.system(size: 8, weight: .semibold)).textCase(.uppercase).opacity(0.7)
                }
                .padding(10).foregroundStyle(BookLook.light(book) ? Theme.ink : Theme.cream)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 8, topTrailingRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
    }
}

/// The pulled-out book: turns from its spine to the cover in 3D; status and page below.
struct BookPullOut: View {
    @EnvironmentObject var state: AppState
    let book: Book
    var onClose: () -> Void
    var onChange: (Book?) -> Void
    @State private var turned = false
    @State private var page = ""
    @State private var photo: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 24) {
                BookCover(book: book)
                    .frame(width: 170, height: 250)
                    .rotation3DEffect(.degrees(turned ? -16 : 90), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .scaleEffect(turned ? 1 : 0.8)
                    .onTapGesture(perform: onClose)
                VStack(alignment: .leading, spacing: 10) {
                    Text(book.title).font(.system(size: 18, weight: .semibold))
                    Text([book.author, book.pages.map { "\($0) с." }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(BookStatus.allCases) { s in
                                Button(s.label) { Task { await patch(.init(status: s.rawValue)) } }
                                    .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 34)
                                    .background(book.status == s ? Theme.olive : Theme.tan.opacity(0.55), in: Capsule())
                                    .foregroundStyle(book.status == s ? Theme.cream : Theme.ink)
                            }
                        }
                    }
                    if book.status == .reading || book.status == .paused {
                        HStack {
                            TextField("сторінка", text: $page).keyboardType(.numberPad).field().frame(width: 120)
                            Button("Зберегти") { Task { await patch(.init(currentPage: Int(page) ?? 0)) } }.font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.olive)
                        }
                    }
                    HStack {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Фото обкладинки", systemImage: "camera") }
                            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.olive)
                        Spacer()
                        Button("Прибрати", role: .destructive) { Task { await remove() } }.font(.system(size: 13.5))
                    }
                    Text("«Хочу» — сама потрапляє в Бажання. Тап поза книгою — поставити назад.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .padding(16).frame(maxWidth: 340)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .offset(y: turned ? 0 : 30).opacity(turned ? 1 : 0)
            }
            .padding(.horizontal, 20)
        }
        .foregroundStyle(Theme.ink)
        .onAppear {
            page = book.currentPage.map(String.init) ?? ""
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { turned = true }
        }
        .onChange(of: photo) { _, item in Task { await upload(item) } }
    }

    private func patch(_ p: API.BookPatch) async {
        if let b = try? await API.current().patchBook(book.id, p) { onChange(b) }
    }
    private func remove() async {
        if (try? await API.current().deleteBook(book.id)) != nil { onChange(nil) }
    }
    private func upload(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
              let jpeg = img.resizedJPEG(maxSide: 1200) else { return }
        if let b = try? await API.current().uploadBookCover(book.id, jpeg: jpeg) { onChange(b) }
    }
}

/// New book: scan the ISBN barcode (VisionKit) → Open Library; or type it in.
struct AddBookSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: BooksPage.AddMode
    var onAdd: (Book) -> Void
    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""
    @State private var cover: String?
    @State private var isbn: String?
    @State private var status: BookStatus = .want
    @State private var mine = true
    @State private var scanning = false
    @State private var note: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            SoftForm {
                if mode == .scan {
                    Section {
                        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                            Button { scanning = true } label: { Label(isbn == nil ? "Сканувати штрихкод" : "Сканувати ще раз", systemImage: "barcode.viewfinder") }
                        } else {
                            Text("Камера-сканер на цьому iPhone недоступна — заповни вручну.").foregroundStyle(Theme.muted)
                        }
                        if let note { Text(note).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    }
                }
                Section {
                    TextField("Назва", text: $title)
                    TextField("Автор", text: $author)
                    TextField("Сторінок", text: $pages).keyboardType(.numberPad)
                }
                Section {
                    Picker("Статус", selection: $status) { ForEach(BookStatus.allCases) { Text($0.label).tag($0) } }
                    Picker("Чия", selection: $mine) { Text("Моя").tag(true); Text(state.partner?.name ?? "").tag(false) }.pickerStyle(.segmented)
                }
            }
            .navigationTitle("Нова книжка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Додати") { Task { await save() } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in scanning = false; Task { await lookup(code) } }.ignoresSafeArea()
            }
            .onAppear { if mode == .scan && DataScannerViewController.isSupported && DataScannerViewController.isAvailable { scanning = true } }
        }
        .tint(Theme.olive)
    }

    private func lookup(_ code: String) async {
        isbn = code
        note = "Шукаю \(code)…"
        do {
            if let f = try await API.current().isbn(code) {
                title = f.title; author = f.author ?? ""; pages = f.pages.map(String.init) ?? ""; cover = f.coverUrl; note = "Знайшов. Перевір і натисни «Додати»."
            } else {
                note = "У базі нема (українських видань там часто нема) — допиши назву, а обкладинку сфотографуєш потім."
            }
        } catch { note = error.localizedDescription }
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            let b = try await API.current().addBook(.init(title: title, author: author.isEmpty ? nil : author, pages: Int(pages), coverUrl: cover, isbn: isbn,
                                                          status: status.rawValue, ownerId: mine ? state.me?.id : state.partner?.id))
            onAdd(b); dismiss()
        } catch { note = error.localizedDescription }
    }
}

/// VisionKit live barcode scanner (EAN-13 / ISBN). Calls back once with the first code.
struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let v = b.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onCode(v)
                    return
                }
            }
        }
    }
}

extension UIImage {
    /// JPEG no bigger than `maxSide` on the long edge.
    func resizedJPEG(maxSide: CGFloat, quality: CGFloat = 0.82) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let img = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return img.jpegData(compressionQuality: quality)
    }
}
