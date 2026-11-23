import SwiftUI

/// Placeholder home (task 5). Tiles arrive in task 13.
struct HomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.olive.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                (Text("Привіт, ") + Text(state.me?.name ?? "").italic().bold() + Text("."))
                    .font(.serif(36))
                    .foregroundStyle(Theme.cream)
                if let p = state.partner {
                    Text("Ви з \(p.name) в одній парі.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.cream.opacity(0.8))
                }
                if state.offline {
                    Label("Немає зв'язку з сервером", systemImage: "wifi.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.cream)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.oliveDeep, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
        }
    }
}
