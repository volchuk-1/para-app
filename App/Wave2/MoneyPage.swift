import SwiftUI

/// «Мої гроші» — only for the member who connected the «Витрати» widget: debt, spending by category, payoff calculator.
struct MoneyPage: View {
    @State private var data: MoneyResult?
    @State private var pay: Double = 0
    @State private var editDebts = false
    @State private var editSettings = false
    @State private var jar: MoneyJar?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(plain: "Мої", italic: "гроші", sub: "Бачиш лише ти" + (data.map { " · віджет — \(ago($0.updatedAt))" } ?? ""))
                if let error { Text(error).font(.system(size: 14)).foregroundStyle(Theme.coffee) }
                if let d = data {
                    if !d.connected {
                        EmptyCard(text: "Підключи віджет «Витрати»: Налаштування → «Ключ для віджета» → скопіюй і встав у Scriptable (меню «Витрати» → «🔗 Підключити DaVincit»).")
                    } else {
                        debtCard(d)
                        spendCard(d)
                        calculator(d)
                        if !(d.cards + d.pumb).isEmpty { cardsCard(d) }
                    }
                } else {
                    ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 130)
        }
        .background(Theme.cream.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load(pay: nil) }
        .sheet(isPresented: $editDebts, onDismiss: { Task { await load() } }) { DebtsSheet(debts: data?.debts ?? []) }
        .sheet(isPresented: $editSettings, onDismiss: { Task { await load(pay: nil) } }) { if let s = data?.settings { MoneySettingsSheet(settings: s) } }
        .sheet(item: $jar, onDismiss: { Task { await load(pay: nil) } }) { j in JarCalcSheet(jar: j, settings: data?.settings) }
    }

    private func load(pay p: Double? = nil) async {
        do { let d = try await API.current().money(pay: p); data = d; pay = d.pay; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func ago(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter.withFractions.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "ще не було" }
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 2 ? "щойно" : m < 60 ? "\(m) хв тому" : m < 1440 ? "\(m / 60) год тому" : d.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA")))
    }

    private func debtCard(_ d: MoneyResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("БОРГ ЗАРАЗ").font(.system(size: 11, weight: .bold)).tracking(1).opacity(0.85)
            Text(MoneyText.uah(d.total)).font(.serif(30, .bold)).padding(.top, 6).padding(.bottom, 8)
            ForEach(d.debts, id: \.self) { x in
                Divider().overlay(Color.white.opacity(0.15))
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(x.name).font(.system(size: 14))
                        Text(debtNote(x)).font(.system(size: 12)).opacity(0.7)
                    }
                    Spacer()
                    Text(MoneyText.uah(x.uah)).font(.system(size: 14, weight: .bold))
                }
                .padding(.vertical, 8)
            }
            if d.debts.isEmpty { Text("Боргів ще не внесено.").font(.system(size: 13)).opacity(0.8) }
            Button("Змінити борги") { editDebts = true }
                .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                .background(.black.opacity(0.22), in: Capsule()).padding(.top, 10)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.olive, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(Theme.cream)
    }

    private func debtNote(_ x: MoneyDebt) -> String {
        var parts: [String] = []
        if x.cur == "$" { parts.append("\(Int(x.amount)) $") }
        parts.append(x.rateMonth > 0 ? String(format: "%.2f %% на місяць", x.rateMonth * 100).replacingOccurrences(of: ".", with: ",")
                     : x.monthly > 0 ? "по \(MoneyText.uah(x.monthly)) на місяць" : "без відсотків")
        if let due = x.due { parts.append("до \(MoneyText.date(due))") }
        if x.live { parts.append("з віджета") }
        return parts.joined(separator: " · ")
    }

    private func spendCard(_ d: MoneyResult) -> some View {
        let maxCat = max(1, d.month.cats.map { max($0.amount, $0.prev) }.max() ?? 1)
        let diff = d.month.spend - d.month.prevSpend
        let month = Calendar.current.component(.month, from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Витрати в \(MoneyText.inMonth[month - 1])").font(.system(size: 15, weight: .bold)); Spacer(); Text(MoneyText.uah(d.month.spend)).font(.system(size: 15, weight: .bold)) }
            Text(d.month.prevSpend > 0 ? "на \(MoneyText.uah(abs(diff))) \(diff <= 0 ? "менше" : "більше"), ніж за ті самі дні минулого місяця · надходження \(MoneyText.uah(d.month.income))"
                 : "З минулим місяцем порівняю, щойно буде з чим · надходження \(MoneyText.uah(d.month.income))")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            ForEach(d.month.cats, id: \.self) { c in
                VStack(spacing: 4) {
                    HStack {
                        Text(c.label).font(.system(size: 14))
                        Spacer()
                        if c.prev > 0 {
                            Text("\(c.amount >= c.prev ? "+" : "−")\(MoneyText.uah(abs(c.amount - c.prev)))").font(.system(size: 12))
                                .foregroundStyle(c.amount > c.prev ? Color(hex: 0xC0453A) : Theme.olive)
                        }
                        Text(MoneyText.uah(c.amount)).font(.system(size: 14, weight: .bold)).frame(minWidth: 70, alignment: .trailing)
                    }
                    GeometryReader { g in
                        Capsule().fill(Theme.ink.opacity(0.07))
                            .overlay(alignment: .leading) { Capsule().fill(c.cat == "fees" ? Color(hex: 0xC0453A) : Theme.olive).frame(width: g.size.width * c.amount / maxCat) }
                    }
                    .frame(height: 6)
                }
            }
            if d.month.cats.isEmpty { Text("Витрат цього місяця ще нема.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
        }
        .padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func calculator(_ d: MoneyResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Калькулятор погашення").font(.system(size: 15, weight: .bold))
            VStack(spacing: 0) {
                row("Зарплата", MoneyText.uah(d.settings.income))
                row("Життя", "−" + MoneyText.uah(d.settings.life))
                ForEach(d.settings.jars) { j in
                    Button { jar = j } label: {
                        HStack {
                            Image(systemName: j.on ? "checkmark.square.fill" : "square").foregroundStyle(Theme.olive)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Банка «\(j.title)»").font(.system(size: 14))
                                Text(j.on ? "відкладаю \(MoneyText.uah(j.monthly)) на місяць" : "не враховується").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(j.on ? "−" + MoneyText.uah(j.monthly) : "—").font(.system(size: 14, weight: .bold))
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                row("Лишається на борг", MoneyText.uah(d.free), bold: true)
                Button("Змінити зарплату й життя") { editSettings = true }
                    .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 34)
                    .background(Theme.tan, in: Capsule()).padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
            .background(Theme.tan.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack { Text("Плачу на місяць").font(.system(size: 14)); Spacer(); Text(MoneyText.uah(pay)).font(.system(size: 14, weight: .bold)) }
            Slider(value: $pay, in: 1000...max(20000, d.free, d.pay), step: 500, onEditingChanged: { editing in
                if !editing { Task { await load(pay: pay) } }
            })
            .tint(Theme.olive)
            ForEach(d.plan, id: \.self) { p in
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.system(size: 14))
                        Text(p.interest > 0 ? "відсотки ≈\(MoneyText.uah(p.interest))" : "без відсотків").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(MoneyText.until(p.done)).font(.system(size: 14, weight: .bold))
                        .foregroundStyle((p.leftAtDue ?? 0) > 0 ? Color(hex: 0xC0453A) : Theme.ink)
                }
                if let left = p.leftAtDue, left > 0 {
                    let total = d.debts.first { $0.name == p.name }?.uah ?? 0
                    Text("До \(MoneyText.date(p.due)) віддаси \(MoneyText.uah(total - left)), лишиться \(MoneyText.uah(left)).\(p.needForDue.map { " Щоб встигнути повністю — ≈\(MoneyText.uah($0)) на місяць." } ?? "")")
                        .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xC0453A))
                }
            }
            Text("Спершу розстрочка за графіком, далі найдорожчий борг, потім решта по черзі. Банка з галочкою — її внесок віднімається від суми на борг.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 4)
        }
        .padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func cardsCard(_ d: MoneyResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Картки").font(.system(size: 15, weight: .bold)).padding(.bottom, 4)
            ForEach(d.cards + d.pumb, id: \.self) { c in row(c.name, c.balance.map { MoneyText.uah($0) } ?? "—") }
            Text("Мінус — це борг на картці. ПУМБ — після звірки у віджеті.").font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 6)
        }
        .padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row(_ l: String, _ v: String, bold: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack { Text(l).font(.system(size: 14, weight: bold ? .bold : .regular)); Spacer(); Text(v).font(.system(size: 14, weight: .bold)) }.padding(.vertical, 8)
            Divider()
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
}

private func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0 }

struct DebtsSheet: View {
    private struct Row: Identifiable { let id = UUID(); var d: MoneyDebt }
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row]
    @State private var error: String?

    init(debts: [MoneyDebt]) { _rows = State(initialValue: debts.map { Row(d: $0) }) }

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { Text("Ставка — на місяць (ПУМБ 2,99). «По … на місяць» — для розстрочки з графіком. «До» — дата, до якої обіцяв віддати.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                ForEach($rows) { $row in
                    let id = row.id
                    Section {
                        TextField("Кому", text: $row.d.name)
                        HStack {
                            TextField("Сума", text: Binding(get: { row.d.amount == 0 ? "" : String(format: "%.2f", row.d.amount) }, set: { row.d.amount = number($0) })).keyboardType(.decimalPad)
                            Picker("", selection: $row.d.cur) { Text("₴").tag("₴"); Text("$").tag("$") }.pickerStyle(.segmented).frame(width: 90)
                        }
                        TextField("% на місяць", text: Binding(get: { row.d.rateMonth == 0 ? "" : String(format: "%.2f", row.d.rateMonth * 100) }, set: { row.d.rateMonth = number($0) / 100 })).keyboardType(.decimalPad)
                        TextField("По … на місяць (розстрочка)", text: Binding(get: { row.d.monthly == 0 ? "" : String(format: "%.2f", row.d.monthly) }, set: { row.d.monthly = number($0) })).keyboardType(.decimalPad)
                        TextField("До (2027-08-30)", text: Binding(get: { row.d.due ?? "" }, set: { row.d.due = $0.isEmpty ? nil : $0 }))
                        if row.d.link == "pumb" { Text("Сума береться з віджета (звірка ПУМБ), якщо вона є.").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                        Button("Прибрати", role: .destructive) { rows.removeAll { $0.id == id } }
                    }
                }
                Section { Button("Додати борг") { rows.append(Row(d: MoneyDebt(name: "", amount: 0, cur: "₴"))) } }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Мої борги").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        do { try await API.current().setDebts(rows.map(\.d).filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct MoneySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var settings: MoneySettings
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section("Зарплата на місяць, ₴ (картка + готівка)") { TextField("30000", text: field(\.income)).keyboardType(.numberPad) }
                Section("На життя, ₴") { TextField("15000", text: field(\.life)).keyboardType(.numberPad) }
                Section("Курс долара для боргів у $") { TextField("45.5", text: field(\.usdRate)).keyboardType(.decimalPad) }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Калькулятор").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
        }
        .tint(Theme.olive)
    }

    private func field(_ k: WritableKeyPath<MoneySettings, Double>) -> Binding<String> {
        Binding(get: { settings[keyPath: k] == 0 ? "" : String(format: k == \MoneySettings.usdRate ? "%.2f" : "%.0f", settings[keyPath: k]) },
                set: { settings[keyPath: k] = number($0) })
    }

    private func save() async {
        do { try await API.current().setMoneySettings(settings); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct JarCalcSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var jar: MoneyJar
    let settings: MoneySettings?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            SoftForm {
                Section { Text("Скільки відкладаєш на місяць? Якщо врахувати — ця сума не піде на борг.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                Section("На місяць, ₴") { TextField("3000", text: Binding(get: { jar.monthly == 0 ? "" : String(format: "%.0f", jar.monthly) }, set: { jar.monthly = number($0) })).keyboardType(.numberPad) }
                Section { Toggle("Враховувати в розрахунку", isOn: $jar.on) }
                if let error { Section { Text(error).foregroundStyle(Theme.coffee) } }
            }
            .navigationTitle("Банка «\(jar.title)»").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } } }
            }
        }
        .tint(Theme.olive)
    }

    private func save() async {
        guard var s = settings else { return }
        s.jars = s.jars.map { $0.id == jar.id ? jar : $0 }
        do { try await API.current().setMoneySettings(s); dismiss() } catch { self.error = error.localizedDescription }
    }
}
