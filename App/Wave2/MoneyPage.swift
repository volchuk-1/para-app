import SwiftUI

/// «Мої гроші» — only for the member who connected the «Витрати» widget: debt, spending by category, payoff calculator.
struct MoneyPage: View {
    @State private var data: MoneyResult?
    @State private var pay: Double = 0
    @State private var editDebts = false
    @State private var editSettings = false
    @State private var jar: MoneyJar?
    @State private var error: String?
    @State private var period = "salary"
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var showAll = false
    @State private var calcOpen = false
    private let periods = [("day", "День"), ("week", "Тиждень"), ("month", "Місяць"), ("salary", "Від зарплати"), ("custom", "Свій")]

    // the cabinet in three bands (Viktor's reference): light top with the balances, a dark band of actions,
    // the olive sheet of spending at the bottom
    var body: some View {
        ScrollView {
            if let d = data, d.connected {
                VStack(spacing: 0) {
                    topBand(d)
                    midBand
                    VStack(alignment: .leading, spacing: 0) {
                        Capsule().fill(.white.opacity(0.3)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.bottom, 12)
                        if let p = d.period { olivePeriod(p, ops: d.ops ?? []) }
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 140)
                    .frame(maxWidth: .infinity, minHeight: 500, alignment: .top)
                    .background(Theme.olive, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous))
                    .foregroundStyle(Theme.cream)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    PageTitle(plain: "Мої", italic: "гроші", sub: nil)
                    if let error { Text(error).font(.system(size: 14)).foregroundStyle(Theme.coffee) }
                    if let d = data, !d.connected {
                        EmptyCard(text: "Підключи віджет «Витрати»: Налаштування → «Ключ для віджета» → скопіюй і встав у Scriptable (меню «Витрати» → «🔗 Підключити DaVincit»).")
                    } else if data == nil {
                        ProgressView().tint(Theme.olive).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8)
            }
        }
        .background(alignment: .top) {
            VStack(spacing: 0) { Theme.paper.frame(height: 300); Color(hex: 0x1A1613) }.ignoresSafeArea()
        }
        .foregroundStyle(Theme.ink)
        .task { await load() }
        .refreshable { await load(pay: nil) }
        .sheet(isPresented: $editDebts, onDismiss: { Task { await load() } }) { DebtsSheet(debts: data?.debts ?? []) }
        .sheet(isPresented: $editSettings, onDismiss: { Task { await load(pay: nil) } }) { if let s = data?.settings { MoneySettingsSheet(settings: s) } }
        .sheet(item: $jar, onDismiss: { Task { await load(pay: nil) } }) { j in JarCalcSheet(jar: j, settings: data?.settings) }
        .sheet(isPresented: $calcOpen) {
            ScrollView { if let d = data { VStack(alignment: .leading, spacing: 10) { Text("Погашення").font(.serif(28, .bold)); calculator(d) }.padding(18) } }
                .background(Theme.cream.ignoresSafeArea()).presentationDetents([.large])
        }
    }

    private func kop(_ v: Double) -> (String, String) {
        let a = abs(v), w = floor(a), k = Int(((a - w) * 100).rounded())
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; f.locale = Locale(identifier: "uk_UA")
        return ((v < 0 ? "−" : "") + (f.string(from: NSNumber(value: w)) ?? "\(Int(w))"), String(format: ",%02d", k))
    }

    private func topBand(_ d: MoneyResult) -> some View {
        let own = d.cards.compactMap(\.balance).reduce(0, +)
        let (whole, cents) = kop(own)
        let jars = d.settings.jars.filter(\.on)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Мої гроші").font(.serif(24, .bold))
                Spacer()
                squareButton("function") { calcOpen = true }
                squareButton("hands.and.sparkles.fill") { editDebts = true }
            }
            .padding(.trailing, 56).padding(.bottom, 14)
            HStack(alignment: .firstTextBaseline) {
                Text("Баланс карток").font(.system(size: 14)).foregroundStyle(Theme.muted)
                Spacer()
                Text(ago(d.updatedAt)).font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 28)
                    .background(Theme.olive, in: Capsule()).foregroundStyle(Theme.cream)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(whole).font(.system(size: 44, weight: .medium)).monospacedDigit()
                Text(cents).font(.system(size: 44, weight: .medium)).foregroundStyle(Color(hex: 0xB9AD9D))
                Text("₴").font(.system(size: 24, weight: .medium)).foregroundStyle(Color(hex: 0xB9AD9D)).padding(.leading, 6)
            }
            .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 2).padding(.bottom, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    c3("hands.and.sparkles.fill", 0xF3DCD6, 0xB8473A, "Борг", MoneyText.uah(d.total), d.plan.last.map { "вільний " + MoneyText.until($0.done).replacingOccurrences(of: "до ", with: "") } ?? "зараз", nil) { editDebts = true }
                    if let pm = d.pumb.first {
                        c3("creditcard.fill", 0xEBDDCB, 0x80513A, "ПУМБ", pm.balance.map { MoneyText.uah($0) } ?? "—", pm.at.map { "звірено " + Date(timeIntervalSince1970: $0 / 1000).formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "uk_UA"))) } ?? "звір у віджеті", nil) { calcOpen = true }
                    }
                    if let p = d.period, let b = p.budget, b > 0, let left = p.budgetLeft {
                        c3("wallet.pass.fill", 0xDFE6D3, 0x4B5E3A, "На життя", MoneyText.uah(left), "з \(MoneyText.uah(b))", left / b) { editSettings = true }
                    }
                    if !jars.isEmpty {
                        c3("banknote.fill", 0xDFE6D3, 0x4B5E3A, "Банки", MoneyText.uah(jars.reduce(0) { $0 + $1.monthly }), "на місяць · \(jars.count)", nil) { calcOpen = true }
                    }
                    ForEach(d.cards, id: \.self) { c in
                        c3("creditcard", 0xEFEAE0, 0x7A6656, c.name, c.balance.map { MoneyText.uah($0) } ?? "—", (c.balance ?? 0) < 0 ? "мінус на картці" : "на картці", nil) { calcOpen = true }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 4)
            }
            .padding(.horizontal, -18)
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
    }

    private func squareButton(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 42, height: 42).background(Theme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            .buttonStyle(PressScale())
    }

    private func c3(_ icon: String, _ bg: UInt32, _ fg: UInt32, _ title: String, _ value: String, _ sub: String, _ bar: Double?, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color(hex: fg)).frame(width: 28, height: 28).background(Color(hex: bg), in: RoundedRectangle(cornerRadius: 9))
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Text(value).font(.system(size: 21, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 14)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                if let bar {
                    GeometryReader { g in Capsule().fill(Theme.ink.opacity(0.1)).overlay(alignment: .leading) { Capsule().fill(Theme.olive).frame(width: g.size.width * max(0.03, min(1, bar))) } }.frame(height: 5).padding(.top, 6)
                }
            }
            .padding(12).frame(width: 150, alignment: .leading)
            .background(Theme.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScale()).foregroundStyle(Theme.ink)
    }

    private var midBand: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill("hands.and.sparkles", "Борги") { editDebts = true }
                pill("function", "Погашення") { calcOpen = true }
                pill("briefcase", "Зарплата й життя") { editSettings = true }
                pill("calendar", "Свій період") { period = "custom"; showAll = false; Task { await load(pay: nil) } }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(Color(hex: 0x1A1613))
    }

    private func pill(_ icon: String, _ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32).overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
                Text(t).font(.system(size: 14, weight: .semibold))
            }
            .padding(.leading, 6).padding(.trailing, 16).frame(height: 44)
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1.5))
            .foregroundStyle(Color(hex: 0xF3EEE6))
        }
        .buttonStyle(PressScale())
    }

    private static let opIcons: [String: String] = ["food": "cart.fill", "cafe": "cup.and.saucer.fill", "taxi": "car.fill", "fuel": "fuelpump.fill", "pharm": "pills.fill", "shop": "bag.fill",
        "deliv": "takeoutbag.and.cup.and.straw.fill", "transp": "bus.fill", "tel": "iphone", "fun": "film.fill", "transfer": "arrow.left.arrow.right", "bills": "house.fill",
        "income": "briefcase.fill", "fees": "exclamationmark.triangle.fill", "inst": "doc.text.fill", "people": "person.2.fill", "cash": "banknote.fill", "debt": "building.columns.fill"]

    /// the spending of a period on the olive sheet: chips, total, budget, categories, operations with white icons
    private func olivePeriod(_ p: MoneyPeriod, ops: [MoneyOp]) -> some View {
        let maxCat = max(1, p.cats.map { max($0.amount, $0.prev) }.max() ?? 1)
        let diff = p.spend - p.prevSpend
        let shown = showAll ? ops : Array(ops.prefix(12))
        let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.date) }.map { DayOps(day: $0.key, ops: $0.value) }.sorted { $0.day > $1.day }
        var daysLeft: Int? = nil
        if p.kind == "salary", let s = p.salaryAt, let d = Evening.date(s) {
            daysLeft = max(1, 30 - (Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0))
        }
        let soft = Theme.cream.opacity(0.7)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(periods, id: \.0) { item in
                        Button(item.1) { period = item.0; showAll = false; Task { await load(pay: nil) } }
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14).frame(height: 32)
                            .background(period == item.0 ? Theme.cream : .white.opacity(0.1), in: Capsule())
                            .foregroundStyle(period == item.0 ? Theme.olive : Theme.cream)
                    }
                }
            }
            if period == "custom" {
                HStack {
                    DatePicker("", selection: $from, displayedComponents: .date).labelsHidden()
                    Text("—")
                    DatePicker("", selection: $to, displayedComponents: .date).labelsHidden()
                    Button("Показати") { Task { await load(pay: nil) } }.font(.system(size: 13, weight: .semibold))
                }
                .environment(\.locale, Locale(identifier: "uk_UA")).colorScheme(.dark)
            }
            HStack { Text(periodTitle(p)).font(.system(size: 18, weight: .bold)); Spacer(); Text(MoneyText.uah(p.spend)).font(.system(size: 18, weight: .bold)) }.padding(.top, 4)
            Text((p.prevSpend > 0 ? "\(MoneyText.uah(abs(diff))) \(diff <= 0 ? "менше" : "більше"), ніж за такий самий період перед цим" : "Порівняння з’явиться, коли буде з чим")
                 + (p.income > 0 ? " · надходження \(MoneyText.uah(p.income))" : "")).font(.system(size: 12.5)).foregroundStyle(soft)
            if let budget = p.budget, budget > 0, let left = p.budgetLeft {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("Бюджет на життя").font(.system(size: 14)); Spacer(); Text(MoneyText.uah(left)).font(.system(size: 14, weight: .bold)); Text("з \(MoneyText.uah(budget))").font(.system(size: 12)).foregroundStyle(soft) }
                    GeometryReader { g in Capsule().fill(.white.opacity(0.14)).overlay(alignment: .leading) { Capsule().fill(left < 0 ? Color(hex: 0xF4B9A8) : Theme.cream).frame(width: g.size.width * min(1, p.spend / budget)) } }.frame(height: 8)
                    if let n = daysLeft, left > 0 { Text("До наступної зарплати ≈\(n) дн. — можна ≈\(MoneyText.uah(left / Double(n))) на день.").font(.system(size: 12.5)).foregroundStyle(soft) }
                }
                .padding(12).background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            ForEach(p.cats, id: \.self) { c in
                VStack(spacing: 4) {
                    HStack {
                        Text(c.label).font(.system(size: 14))
                        Spacer()
                        if c.prev > 0 { Text("\(c.amount >= c.prev ? "+" : "−")\(MoneyText.uah(abs(c.amount - c.prev)))").font(.system(size: 12)).foregroundStyle(c.amount > c.prev ? Color(hex: 0xF4B9A8) : Color(hex: 0xCFE3B5)) }
                        Text(MoneyText.uah(c.amount)).font(.system(size: 14, weight: .bold)).frame(minWidth: 70, alignment: .trailing)
                    }
                    GeometryReader { g in Capsule().fill(.white.opacity(0.14)).overlay(alignment: .leading) { Capsule().fill(c.cat == "fees" ? Color(hex: 0xF4B9A8) : Theme.cream).frame(width: g.size.width * c.amount / maxCat) } }.frame(height: 6)
                }
            }
            if p.cats.isEmpty { Text("За цей період витрат нема.").font(.system(size: 13)).foregroundStyle(soft) }
            Text("Операції").font(.system(size: 18, weight: .bold)).padding(.top, 10)
            ForEach(days) { day in
                Text(day.day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))).uppercased())
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(soft).padding(.top, 8)
                ForEach(day.ops) { o in
                    HStack(spacing: 12) {
                        Image(systemName: Self.opIcons[o.cat] ?? (o.income ? "arrow.down.left" : "creditcard.fill")).font(.system(size: 17))
                            .foregroundStyle(Theme.ink).frame(width: 42, height: 42).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.merchant ?? o.label ?? "").font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                            Text([o.label, o.card, o.date.formatted(.dateTime.hour().minute())].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(soft).lineLimit(1)
                        }
                        Spacer()
                        Text(o.amount.map { (o.income ? "+" : "−") + MoneyText.uah($0) } ?? "—").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(o.income ? Color(hex: 0xCFE3B5) : Theme.cream)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
                }
            }
            if ops.isEmpty { Text("Операцій нема.").font(.system(size: 13)).foregroundStyle(soft) }
            if ops.count > shown.count {
                Button("Показати всі (\(ops.count))") { showAll = true }
                    .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 34).background(.white.opacity(0.14), in: Capsule()).padding(.top, 6)
            }
        }
    }

    private func load(pay p: Double? = nil) async {
        do {
            let d = try await API.current().money(pay: p, period: period, from: Evening.iso(from), to: Evening.iso(to))
            data = d; pay = d.pay; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func periodTitle(_ p: MoneyPeriod) -> String {
        switch p.kind {
        case "day": return "Сьогодні"
        case "week": return "Цей тиждень"
        case "month": return "Витрати в \(MoneyText.inMonth[Calendar.current.component(.month, from: Date()) - 1])"
        case "salary": return "Від зарплати" + (p.salaryAt.map { " " + MoneyText.date($0).split(separator: " ").prefix(2).joined(separator: " ") } ?? "")
        default: return "\(MoneyText.date(p.from)) – \(MoneyText.date(p.to))"
        }
    }

    private func periodCard(_ p: MoneyPeriod, ops: [MoneyOp]) -> some View {
        let maxCat = max(1, p.cats.map { max($0.amount, $0.prev) }.max() ?? 1)
        let diff = p.spend - p.prevSpend
        let shown = showAll ? ops : Array(ops.prefix(12))
        let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.date) }.map { DayOps(day: $0.key, ops: $0.value) }.sorted { $0.day > $1.day }
        var daysLeft: Int? = nil
        if p.kind == "salary", let s = p.salaryAt, let d = Evening.date(s) {
            daysLeft = max(1, 30 - (Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0))
        }
        let compare = (p.prevSpend > 0 ? "\(MoneyText.uah(abs(diff))) \(diff <= 0 ? "менше" : "більше"), ніж за такий самий період перед цим" : "Порівняння з’явиться, коли буде з чим")
            + (p.income > 0 ? " · надходження \(MoneyText.uah(p.income))" : "")
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(periods, id: \.0) { item in
                        Button(item.1) { period = item.0; showAll = false; Task { await load(pay: nil) } }
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 13).frame(height: 34)
                            .background(period == item.0 ? Theme.ink : Theme.tan, in: Capsule())
                            .foregroundStyle(period == item.0 ? Theme.paper : Theme.ink)
                    }
                }
            }
            if period == "custom" {
                HStack {
                    DatePicker("", selection: $from, displayedComponents: .date).labelsHidden()
                    Text("—")
                    DatePicker("", selection: $to, displayedComponents: .date).labelsHidden()
                    Button("Показати") { Task { await load(pay: nil) } }.font(.system(size: 13, weight: .semibold))
                }
                .environment(\.locale, Locale(identifier: "uk_UA"))
            }
            HStack { Text(periodTitle(p)).font(.system(size: 15, weight: .bold)); Spacer(); Text(MoneyText.uah(p.spend)).font(.system(size: 15, weight: .bold)) }
            Text(compare).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            if let budget = p.budget, budget > 0, let left = p.budgetLeft {
                budgetBox(spend: p.spend, budget: budget, left: left, daysLeft: daysLeft)
            }
            ForEach(p.cats, id: \.self) { c in catRow(c, maxCat: maxCat) }
            if p.cats.isEmpty { Text("За цей період витрат нема.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            Text("Операції").font(.system(size: 15, weight: .bold)).padding(.top, 8)
            ForEach(days) { day in
                Text(day.day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "uk_UA"))).uppercased())
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 6)
                ForEach(day.ops) { o in opRow(o) }
            }
            if ops.isEmpty { Text("Операцій нема.").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            if ops.count > shown.count {
                Button("Показати всі (\(ops.count))") { showAll = true }
                    .font(.system(size: 13.5, weight: .semibold)).padding(.horizontal, 14).frame(height: 34).background(Theme.tan, in: Capsule())
            }
        }
        .padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func budgetBox(spend: Double, budget: Double, left: Double, daysLeft: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Бюджет на життя").font(.system(size: 14))
                Spacer()
                Text(MoneyText.uah(left)).font(.system(size: 14, weight: .bold))
                Text("з \(MoneyText.uah(budget))").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            GeometryReader { g in
                Capsule().fill(Theme.ink.opacity(0.07))
                    .overlay(alignment: .leading) { Capsule().fill(left < 0 ? Color(hex: 0xC0453A) : Theme.olive).frame(width: g.size.width * min(1, spend / budget)) }
            }
            .frame(height: 8)
            if let n = daysLeft, left > 0 { Text("До наступної зарплати ≈\(n) дн. — можна ≈\(MoneyText.uah(left / Double(n))) на день.").font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
            if left < 0 { Text("Бюджет перевищено.").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xC0453A)) }
        }
        .padding(12).background(Theme.tan.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func catRow(_ c: MoneyCat, maxCat: Double) -> some View {
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

    private func opRow(_ o: MoneyOp) -> some View {
        let src = ["wallet": "Гаманець", "manual": "вручну", "mono": "mono"][o.src ?? ""] ?? o.src
        let meta = [o.label, o.card, src, o.date.formatted(.dateTime.hour().minute())].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.merchant ?? o.label ?? "").font(.system(size: 14)).lineLimit(1)
                    Text(meta).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text(o.amount.map { (o.income ? "+" : "−") + MoneyText.uah($0) } ?? "—").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(o.income ? Theme.olive : Theme.ink)
            }
            .padding(.vertical, 6)
            Divider()
        }
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

private struct DayOps: Identifiable { let day: Date; let ops: [MoneyOp]; var id: Date { day } }

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
