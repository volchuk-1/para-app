import SwiftUI

/// Splash → «Створити пару» / «Приєднатися».
struct OnboardingView: View {
    enum Step { case start, create, join, code(PairResult) }
    @State private var step: Step = .start

    var body: some View {
        ZStack {
            Theme.olive.ignoresSafeArea()
            switch step {
            case .start: StartView(step: $step)
            case .create: CreatePairView(step: $step)
            case .join: JoinPairView(step: $step)
            case .code(let r): PairCodeView(result: r)
            }
        }
        .foregroundStyle(Theme.cream)
        .animation(.easeInOut(duration: 0.25), value: stepKey)
    }

    private var stepKey: Int {
        switch step { case .start: 0; case .create: 1; case .join: 2; case .code: 3 }
    }
}

struct Logo: View {
    var size: CGFloat = 50
    var body: some View {
        VStack(spacing: 12) {
            (Text("Da") + Text("Vi").italic() + Text("ncit"))
                .font(.serif(size))
                .tracking(2)
            Text("AMOR VINCIT OMNIA")
                .font(.system(size: 11, weight: .medium))
                .tracking(3.5)
                .opacity(0.75)
        }
    }
}

private struct StartView: View {
    @Binding var step: OnboardingView.Step
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Logo()
            Spacer()
            Text("Дарина & Віктор.\nНаш календар, бажання, спогади.")
                .font(.system(size: 12, weight: .medium))
                .tracking(1.6)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0.85)
                .padding(.bottom, 10)
            Button("Створити пару") { step = .create }
                .buttonStyle(PillButtonStyle(fill: Theme.cream, text: Theme.espresso))
            Button("У мене є код") { step = .join }
                .buttonStyle(PillButtonStyle(fill: Theme.oliveDeep, text: Theme.cream))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct CreatePairView: View {
    @EnvironmentObject var state: AppState
    @Binding var step: OnboardingView.Step
    @State private var myName = ""
    @State private var partnerName = ""
    @State private var myRole = "m"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackButton { step = .start }
            Text("Створюємо пару").font(.serif(34, .bold))
            Text("Ти отримаєш код. Партнер введе його у своєму DaVincit.")
                .font(.system(size: 15)).opacity(0.8)
            TextField("Твоє ім'я", text: $myName).field().textContentType(.givenName)
            TextField("Ім'я партнера", text: $partnerName).field()
            Picker("Я", selection: $myRole) {
                Text("Я — він").tag("m")
                Text("Я — вона").tag("f")
            }
            .pickerStyle(.segmented)
            if let error { Text(error).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.biscuit) }
            Spacer()
            Button {
                Task { await create() }
            } label: {
                if busy { ProgressView().tint(Theme.espresso) } else { Text("Створити") }
            }
            .buttonStyle(PillButtonStyle(fill: Theme.cream, text: Theme.espresso))
            .disabled(busy || myName.trimmingCharacters(in: .whitespaces).isEmpty || partnerName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24)
    }

    private func create() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let r = try await API.current().createPair(myName: myName, partnerName: partnerName, myRole: myRole)
            KeyStore.deviceKey = r.deviceKey
            step = .code(r)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PairCodeView: View {
    @EnvironmentObject var state: AppState
    let result: PairResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            TagLabel(text: "Код для \(result.partner?.name ?? "партнера")")
            Text(spaced(result.pairCode ?? ""))
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .tracking(4)
                .textSelection(.enabled)
            Text("Код діє 24 години і спрацює один раз. Надішли його \(result.partner?.name ?? "партнеру") — у DaVincit треба натиснути «У мене є код».")
                .font(.system(size: 15)).opacity(0.85)
            Spacer()
            ShareLink(item: "Код для DaVincit: \(result.pairCode ?? "")") {
                Label("Надіслати код", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.oliveDeep, text: Theme.cream))
            Button("Готово") { state.paired(result) }
                .buttonStyle(PillButtonStyle(fill: Theme.cream, text: Theme.espresso))
        }
        .padding(24)
    }

    private func spaced(_ c: String) -> String {
        guard c.count == 6 else { return c }
        return String(c.prefix(3)) + " " + String(c.suffix(3))
    }
}

private struct JoinPairView: View {
    @EnvironmentObject var state: AppState
    @Binding var step: OnboardingView.Step
    @State private var code = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackButton { step = .start }
            Text("Приєднуємось").font(.serif(34, .bold))
            Text("Введи код, який тобі надіслали.").font(.system(size: 15)).opacity(0.8)
            TextField("Код, наприклад ABC 234", text: $code)
                .field()
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
            TextField("Твоє ім'я (якщо треба виправити)", text: $name).field()
            if let error { Text(error).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.biscuit) }
            Spacer()
            Button {
                Task { await join() }
            } label: {
                if busy { ProgressView().tint(Theme.espresso) } else { Text("Приєднатися") }
            }
            .buttonStyle(PillButtonStyle(fill: Theme.cream, text: Theme.espresso))
            .disabled(busy || code.filter { !$0.isWhitespace }.count < 6)
        }
        .padding(24)
    }

    private func join() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let r = try await API.current().join(code: code, name: trimmed.isEmpty ? nil : trimmed)
            state.paired(r)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Theme.oliveDeep, in: Circle())
        }
        .foregroundStyle(Theme.cream)
    }
}
