import SwiftUI
import WebKit

/// The page, with the system's tab bar over its foot. The site holds every tab
/// in one document, so there is one web view and it never moves: the bar is a
/// separate system tab bar laid over it, and a press on the bar asks the page
/// to switch tab. (A SwiftUI TabView would move the web view between its tab
/// containers on every switch.)
struct RootView: View {
    let shell: Shell
    let lock: AppLock
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            Color(uiColor: shell.paper).ignoresSafeArea()
            ZStack(alignment: .bottom) {
                WebHost(webView: shell.webView)
                    .ignoresSafeArea()
                if !shell.tabs.isEmpty {
                    SystemTabBar(shell: shell)
                        .ignoresSafeArea(edges: .bottom)
                        .offset(y: shell.barHidden ? 160 : 0)
                        .opacity(shell.barHidden ? 0 : 1)
                        .allowsHitTesting(!shell.barHidden)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: shell.barHidden)
            .animation(.easeInOut(duration: 0.22), value: shell.tabs.isEmpty)
            .opacity(shell.shown ? 1 : 0)
            if shell.phase == .offline {
                OfflineView(lang: shell.lang) { shell.retry() }
                    .transition(.opacity)
            }
            if lock.enabled && (lock.locked || lock.covered) {
                LockView(lang: shell.lang, asks: lock.locked) {
                    lock.unlock(reason: L10n.t("lockReason", shell.lang))
                }
                .transition(.opacity)
            }
        }
        // The keyboard rises over the page and the bar; the page moves its own
        // fields into view (as it does in Safari).
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(shell.scheme)
        .tint(Color(uiColor: shell.ink))
        .onChange(of: phase, initial: true) { _, next in
            lock.phaseChanged(next, reason: L10n.t("lockReason", shell.lang))
            if next == .active { shell.becameActive() }
        }
        .onOpenURL { url in shell.open(url) }
    }
}

/// The system's own tab bar, standing alone over the page: the page's tabs,
/// their names and marks, the open one lit in the page's ink. A press on the
/// open tab again takes the page back to its top.
struct SystemTabBar: UIViewRepresentable {
    let shell: Shell

    func makeCoordinator() -> Coordinator { Coordinator(shell: shell) }

    func makeUIView(context: Context) -> MeasuredTabBar {
        let bar = MeasuredTabBar()
        bar.delegate = context.coordinator
        bar.onHeight = { [weak shell] height in shell?.setBarInset(height) }
        return bar
    }

    func updateUIView(_ bar: MeasuredTabBar, context: Context) {
        context.coordinator.shell = shell
        let tabs = shell.tabs
        let signature = tabs.map { "\($0.key)|\($0.label)|\($0.iconID)" }.joined(separator: ",")
        if bar.signature != signature {
            bar.signature = signature
            let fallback = UIImage(systemName: "square.dashed")
            let items = tabs.enumerated().map { index, tab in
                let item = UITabBarItem(title: tab.label, image: tab.icon ?? fallback, selectedImage: tab.iconOn ?? tab.icon ?? fallback)
                item.tag = index
                return item
            }
            bar.setItems(items, animated: false)
            context.coordinator.keys = tabs.map(\.key)
        }
        if let index = tabs.firstIndex(where: { $0.key == shell.selected }),
           let items = bar.items, index < items.count, bar.selectedItem !== items[index] {
            bar.selectedItem = items[index]
        }
        bar.tintColor = shell.ink
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MeasuredTabBar, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.window?.bounds.width ?? 390
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var shell: Shell
        var keys: [String] = []

        init(shell: Shell) { self.shell = shell }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard item.tag >= 0, item.tag < keys.count else { return }
            shell.pick(keys[item.tag])
        }
    }
}

/// A tab bar that says how tall it is once it knows (it grows by the home
/// indicator's room when it reaches the screen's foot).
final class MeasuredTabBar: UITabBar {
    var signature = ""
    var onHeight: ((CGFloat) -> Void)?

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > 0 { onHeight?(bounds.height) }
    }
}

/// The holder of the one page.
struct WebHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WebHostView {
        let host = WebHostView()
        host.adopt(webView)
        return host
    }

    func updateUIView(_ host: WebHostView, context: Context) {
        host.adopt(webView)
    }
}

final class WebHostView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func adopt(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }
}
