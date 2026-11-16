import SwiftUI

/// The first load found no connection (once the site's offline copy is in
/// place, a Release build opens from it instead).
struct OfflineView: View {
    let lang: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .padding(.bottom, 6)
            Text(L10n.t("offlineTitle", lang))
                .font(.system(.title3, design: .serif).weight(.bold))
            Text(L10n.t("offlineBody", lang))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #if DEBUG
            Text(AppConfig.baseURL.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            #endif
            Button(L10n.t("retry", lang), action: retry)
                .buttonStyle(.bordered)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground"))
    }
}

/// Over the page while the app is locked, and in the app switcher.
struct LockView: View {
    let lang: String
    /// Locked (with a way to unlock), as against only covered.
    let asks: Bool
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
            if asks {
                Text(L10n.t("lockTitle", lang))
                    .font(.system(.title3, design: .serif).weight(.bold))
                Button(L10n.t("unlock", lang), action: unlock)
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
    }
}
