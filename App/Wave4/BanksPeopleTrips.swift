import SwiftUI
import PhotosUI

// MARK: - Разом → Банки

/// monobank jars with a category and who sees them. New jars: only the owner sees them until set up.
struct BanksPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var data: Finance4?
    @State private var cat: String?
    @State private var edit: Jar4?
    @State private var trip: Trip?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: "Наші", italic: "банки", sub: "Банки monobank з категоріями. Нові спершу бачиш лише ти.")
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coffee) }
                if let d = data {
                    if !d.connected { EmptyCard(text: "monobank ще не підключено на сервері.") }
                    ForEach(d.jars.filter(\.isNew)) { j in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("НОВА БАНКА В MONO").font(.system(size: 11, weight: .bold)).tracking(1).opacity(0.85)
                            Text(j.title).font(.serif(22, .bold))
                            Text("Бачиш лише ти. Обери категорію — і чи показувати \(state.partner?.name ?? "").").font(.system(size: 13)).opacity(0.85)
                            Button("Налаштувати") { edit = j }.font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                                .background(Theme.tan, in: Capsule()).foregroundStyle(Theme.ink).padding(.top, 4)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).foregroundStyle(Theme.cream)
                    }
                    let ready = d.jars.filter { !$0.isNew }
                    let cats = Jar4.categories.filter { c in ready.contains { $0.category == c.0 } }
                    if cats.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                chip(nil, "Усі")
                                ForEach(cats, id: \.0) { c in chip(c.0, c.1) }
                            }
                            .padding(.horizontal, 18)
                        }
                        .padding(.horizontal, -18)
                    }
                    ForEach(ready.filter { cat == nil || $0.category == cat }) { j in jarCard(j, owner: d.owner == true) }
                    if let h = d.hidden, !h.isEmpty {
                        Button { edit = h[0] } label: {
                            Text("Сховано: \(h.map(\.title).joined(separator: ", ")) · змінити").font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(30)
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $edit, onDismiss: { Task { await load() } }) { j in JarSheet(jar: j, partner: state.partner?.name ?? "") }
        .sheet(item: $trip) { t in TripSheet(trip: t, jars: data?.jars ?? []) }
    }

    private func chip(_ k: String?, _ l: String) -> some View {
        Button { cat = k } label: {
            Text(l).font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
                .background(cat == k ? Theme.ink : Theme.tan.opacity(0.6), in: Capsule()).foregroundStyle(cat == k ? Theme.paper : Theme.ink)
        }
        .buttonStyle(.plain)
    }

    private func jarCard(_ j: Jar4, owner: Bool) -> some View {
        let pc = j.goal.map { $0 > 0 ? min(1, j.balance / $0) : 0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(j.categoryLabel.uppercased(), systemImage: j.categoryIcon).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.olive)
                Spacer()
                Text(Jar4.seen[j.visibility] ?? "").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Text(j.title).font(.serif(22, .bold))
            if let p = j.purpose, !p.isEmpty { Text(p).font(.system(size: 13)).foregroundStyle(Theme.muted) }
            HStack {
                Text(MoneyText.uah(j.balance) + (j.goal.map { " з \(MoneyText.uah($0))" } ?? "")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                if let pc { Text("\(Int(pc * 100))%").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            }
            if let pc {
                GeometryReader { g in Capsule().fill(Theme.ink.opacity(0.07)).overlay(alignment: .leading) { Capsule().fill(Theme.olive).frame(width: max(4, g.size.width * pc)) } }.frame(height: 8)
            }
            if let per = j.plan.perMonth, let due = j.due {
                Text("по \(MoneyText.uah(per)) на місяць, щоб встигнути до \(MoneyText.date(due))").font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else if let eta = j.plan.eta, let m = j.monthly {
                Text("по \(MoneyText.uah(m)) на місяць — збереться \(MoneyText.until(eta))").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 6) {
                if let u = j.topUpUrl?.asURL { small("Поповнити", "plus") { openURL(u) } }
                if owner { small("Налаштувати", "pencil") { edit = j } }
                if j.category == "trip" { small("Поїздка", "suitcase.rolling") { var t = Trip(); t.jarId = j.id; trip = t } }
            }
            .padding(.top, 4)
        }
        .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func small(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Label(t, systemImage: icon).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 34).background(Theme.tan, in: Capsule()) }
            .buttonStyle(.plain)
    }

    private func load() async {
        do { data = try await API.current().finance4(); error = nil } catch { self.error = error.localizedDescription }
    }
}

struct JarSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jar: Jar4
    let partner: String
    @State private var category = "other"
    @State private var visibility = "me"
    @State private var purpose = ""
    @State private var withDate = false
    @State private var due = Date()
    @State private var monthly = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { Text("Назва й сума — з monobank, змінюються там.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                Section("Категорія") {
                    Picker("Категорія", selection: $category) { ForEach(Jar4.categories, id: \.0) { Label($0.1, systemImage: $0.2).tag($0.0) } }
                }
                Section {
                    Picker("Хто бачить", selection: $visibility) { Text("Обоє").tag("both"); Text("Лише я").tag("me"); Text("Сховати").tag("hidden") }.pickerStyle(.segmented)
                } header: { Text("Хто бачить") } footer: { Text("«Лише я» — для сюрпризу \(partner). «Сховати» — для боргу й особистого.") }
                Section("Для чого") { TextField("позаплановий відпочинок", text: $purpose) }
                Section {
                    Picker("", selection: $withDate) { Text("Без дати").tag(false); Text("Є дата").tag(true) }.pickerStyle(.segmented)
                    if withDate { DatePicker("До", selection: $due, displayedComponents: .date).environment(\.locale, Locale(identifier: "uk_UA")) }
                    else { TextField("Скільки відкладаємо на місяць, ₴", text: $monthly).keyboardType(.numberPad) }
                } footer: { Text(withDate ? "Порахую, скільки відкладати на місяць, щоб встигнути." : "Порахую, коли збереться при такому внеску.") }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Банка «\(jar.title)»").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
            .onAppear {
                category = jar.isNew ? "other" : jar.category; visibility = jar.visibility; purpose = jar.purpose ?? ""
                withDate = jar.due != nil; due = jar.due.flatMap { Evening.date($0) } ?? Date(); monthly = jar.monthly.map { String(Int($0)) } ?? ""
            }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        let m = Double(monthly.replacingOccurrences(of: " ", with: ""))
        do {
            try await API.current().setJar(jar.id, .init(category: category, visibility: visibility, purpose: purpose.isEmpty ? nil : purpose,
                                                        due: withDate ? Evening.iso(due) : nil, monthly: withDate ? nil : m))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Близькі й дні народження

struct PeopleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var people: [Person] = []
    @State private var name = ""
    @State private var relation = ""
    @State private var day = 1
    @State private var month = 1
    @State private var year = ""
    @State private var error: String?
    private let months = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { Text("Дні народження з'являться в календарі обох. За 3 тижні нагадаю й запропоную відкрити збір.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                Section("Близькі") {
                    ForEach(people) { p in
                        HStack {
                            Text("🎂")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 15, weight: .semibold))
                                Text([p.relation, MoneyText.date(p.next), p.turns.map { "\($0) р." }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(p.daysLeft == 0 ? "сьогодні" : p.daysLeft == 1 ? "завтра" : "за \(p.daysLeft) дн.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.olive)
                        }
                        .swipeActions { Button("Прибрати", role: .destructive) { Task { try? await API.current().deletePerson(p.id); await load() } } }
                    }
                    if people.isEmpty { Text("Поки нікого.").foregroundStyle(Theme.muted) }
                }
                Section("Додати") {
                    TextField("Ім'я — Мама", text: $name)
                    TextField("Хто це — моя мама, подруга Дарини…", text: $relation)
                    Picker("День", selection: $day) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                    Picker("Місяць", selection: $month) { ForEach(1...12, id: \.self) { Text(months[$0 - 1]).tag($0) } }
                    TextField("Рік (необов'язково)", text: $year).keyboardType(.numberPad)
                    Button("Додати") { Task { await add() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error { Text(error).foregroundStyle(Theme.coffee) }
                }
            }
            .navigationTitle("Близькі").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task { await load() }
        }
        .tint(Theme.olive)
    }

    private func load() async { people = (try? await API.current().people()) ?? people }
    private func add() async {
        do {
            _ = try await API.current().addPerson(.init(name: name, relation: relation.isEmpty ? nil : relation, birthday: String(format: "%02d-%02d", month, day), year: Int(year)))
            name = ""; relation = ""; year = ""; error = nil
            await load()
        } catch { self.error = "Перевір дату: такого дня в цьому місяці нема" }
    }
}

// MARK: - Поїздка

struct TripsBlock: View {
    @State private var trips: [Trip] = []
    @State private var open: Trip?
    @State private var jars: [Jar4] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Поїздки").font(.system(size: 15, weight: .bold))
                Spacer()
                Button { open = Trip() } label: { Label("Нова", systemImage: "plus").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32).background(Theme.tan, in: Capsule()) }
                    .buttonStyle(.plain)
            }
            ForEach(trips) { t in
                Button { open = t } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "suitcase.rolling.fill").font(.system(size: 20)).foregroundStyle(Theme.olive)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.system(size: 15, weight: .semibold))
                            Text([t.place, t.from.map { MoneyText.date($0) }, t.nights.map { "\($0) ноч." }, t.budget.map { MoneyText.uah($0) }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            if trips.isEmpty { Text("Ще нема. Чернетку заповнюєте разом, поступово.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
        }
        .padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task { await load() }
        .sheet(item: $open, onDismiss: { Task { await load() } }) { t in TripSheet(trip: t, jars: jars) }
    }

    private func load() async {
        trips = (try? await API.current().trips()) ?? trips
        jars = (try? await API.current().finance4().jars) ?? jars
    }
}

struct TripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip
    let jars: [Jar4]
    @State private var hasDates = false
    @State private var from = Date()
    @State private var to = Date().addingTimeInterval(2 * 86400)
    @State private var budget = ""
    @State private var newItem = ""
    @State private var planDay = Date()
    @State private var planText = ""
    @State private var weather: WeatherResult?
    @State private var error: String?
    @State private var confirmDelete = false
    private let transports = [("car", "Авто"), ("train", "Потяг"), ("bus", "Автобус"), ("plane", "Літак"), ("other", "Інше")]

    var body: some View {
        NavigationStack {
            SoftForm {
                Section("Куди") {
                    TextField("Назва — Карпати", text: $trip.title)
                    TextField("Місто — Яремче", text: Binding(get: { trip.place ?? "" }, set: { trip.place = $0 }))
                }
                Section("Коли") {
                    Toggle("Є дати", isOn: $hasDates)
                    if hasDates {
                        DatePicker("З", selection: $from, displayedComponents: .date)
                        DatePicker("До", selection: $to, in: from..., displayedComponents: .date)
                    }
                }
                .environment(\.locale, Locale(identifier: "uk_UA"))
                Section("Бюджет") {
                    TextField("Скільки, ₴", text: $budget).keyboardType(.numberPad)
                    Picker("З банки", selection: Binding(get: { trip.jarId ?? "" }, set: { trip.jarId = $0.isEmpty ? nil : $0 })) {
                        Text("—").tag("")
                        ForEach(jars) { j in Text("\(j.title) · \(MoneyText.uah(j.balance))").tag(j.id) }
                    }
                }
                Section("Дорога") {
                    Picker("Чим", selection: Binding(get: { trip.transport ?? "car" }, set: { trip.transport = $0 })) { ForEach(transports, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
                    TextField("Деталі — 3 год 40 хв, пальне ≈1 400 ₴", text: Binding(get: { trip.road ?? "" }, set: { trip.road = $0 }))
                }
                Section("Житло") {
                    TextField("Назва", text: Binding(get: { trip.stay?.name ?? "" }, set: { stay { $0.name = $1 }($0) }))
                    TextField("Посилання", text: Binding(get: { trip.stay?.url ?? "" }, set: { stay { $0.url = $1.isEmpty ? nil : $1 }($0) })).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Заїзд — 14:00", text: Binding(get: { trip.stay?.checkIn ?? "" }, set: { stay { $0.checkIn = $1.isEmpty ? nil : $1 }($0) }))
                    TextField("Виїзд — 11:00", text: Binding(get: { trip.stay?.checkOut ?? "" }, set: { stay { $0.checkOut = $1.isEmpty ? nil : $1 }($0) }))
                    Toggle("Заброньовано", isOn: Binding(get: { trip.stay?.booked ?? false }, set: { v in var s = trip.stay ?? TripStay(); s.booked = v; trip.stay = s }))
                }
                Section("Що взяти") {
                    ForEach(trip.packing.indices, id: \.self) { i in Toggle(trip.packing[i].t, isOn: $trip.packing[i].done) }
                        .onDelete { trip.packing.remove(atOffsets: $0) }
                    HStack { TextField("Термос, шапки…", text: $newItem); Button("Додати") { add() }.disabled(newItem.isEmpty) }
                }
                Section("План по днях") {
                    ForEach(Array(trip.plan.enumerated()), id: \.offset) { _, p in
                        Text((p.day.map { MoneyText.date($0) + " — " } ?? "") + p.text).font(.system(size: 14))
                    }
                    .onDelete { trip.plan.remove(atOffsets: $0) }
                    DatePicker("День", selection: $planDay, displayedComponents: .date).environment(\.locale, Locale(identifier: "uk_UA"))
                    HStack { TextField("Водоспад, чани…", text: $planText); Button("Додати") { trip.plan.append(PlanItem(day: Evening.iso(planDay), text: planText)); planText = "" }.disabled(planText.isEmpty) }
                }
                if !trip.id.isEmpty {
                    Section("Погода") {
                        if let w = weather {
                            if w.days.isEmpty { Text(w.note ?? "").foregroundStyle(Theme.muted) }
                            ForEach(w.days, id: \.self) { d in
                                HStack { Text(MoneyText.date(d.date)); Spacer(); Text("\(d.max)° / \(d.min)°").bold(); if let r = d.rain { Text("опади \(r)%").foregroundStyle(Theme.muted) } }.font(.system(size: 14))
                            }
                        } else { ProgressView() }
                    }
                    Section { Button("Видалити поїздку", role: .destructive) { confirmDelete = true } }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle(trip.id.isEmpty ? "Нова поїздка" : trip.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрити") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(trip.id.isEmpty ? "Створити" : "Зберегти") { Task { await save() } }.disabled(trip.title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("Видалити поїздку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Видалити", role: .destructive) { Task { try? await API.current().deleteTrip(trip.id); dismiss() } }
            }
            .onAppear {
                hasDates = trip.from != nil
                from = trip.from.flatMap { Evening.date($0) } ?? Date(); to = trip.to.flatMap { Evening.date($0) } ?? from.addingTimeInterval(2 * 86400)
                budget = trip.budget.map { String(Int($0)) } ?? ""
            }
            .task { if !trip.id.isEmpty { weather = try? await API.current().tripWeather(trip.id) } }
        }
        .tint(Theme.olive)
    }

    private func stay(_ f: @escaping (inout TripStay, String) -> Void) -> (String) -> Void {
        { v in var s = trip.stay ?? TripStay(); f(&s, v); trip.stay = s }
    }
    private func add() { trip.packing.append(PackItem(t: newItem)); newItem = "" }

    private func save() async {
        var t = trip
        t.from = hasDates ? Evening.iso(from) : nil
        t.to = hasDates ? Evening.iso(to) : nil
        t.budget = Double(budget.replacingOccurrences(of: " ", with: ""))
        do { _ = try await API.current().saveTrip(t); dismiss() } catch { self.error = error.localizedDescription }
    }
}
