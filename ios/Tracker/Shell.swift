import SwiftUI
import UIKit
import UserNotifications
import WebKit
import WidgetKit

/// One of the page's main tabs, as the app's bar shows it.
struct ShellTab: Identifiable, Equatable {
    let key: String
    let label: String
    /// The page's own icon, drawn by the page into a PNG; `iconOn` is the
    /// filled one it shows for the tab that is open (none for a solid mark).
    let icon: UIImage?
    let iconOn: UIImage?
    let iconID: String
    var id: String { key }

    static func == (a: ShellTab, b: ShellTab) -> Bool {
        a.key == b.key && a.label == b.label && a.iconID == b.iconID
    }
}

/// The app: one page (the whole site is one document holding every tab), kept
/// alive for as long as the app runs, and the system's tab bar over it,
/// which follows the page's tabs. Everything the page and the app say to
/// each other goes through here.
@Observable
final class Shell: NSObject {
    enum Phase: Equatable { case loading, ready, offline }

    /// The page's main tabs, in its order, without the ones it has hidden.
    /// Empty while signed out (or on a page that does not speak to the app):
    /// then there is no bar.
    var tabs: [ShellTab] = []
    var selected = ""
    /// The page has something over everything (a dialog, a settings page):
    /// the bar steps aside for it, as the page's own bar did.
    var barHidden = false
    var phase: Phase = .loading
    /// Hidden until the page has drawn itself in its own theme, so a dark
    /// page never flashes light.
    var shown = false
    /// nil follows the phone (the page's "System" theme).
    var scheme: ColorScheme?
    var paper: UIColor
    var ink: UIColor
    var lang: String

    @ObservationIgnored let lock: AppLock
    @ObservationIgnored private var madeWebView: WKWebView?

    /// The one page. It is made the first time it is asked for (when its
    /// holder goes on screen), never in `init`: the app's `init` runs before
    /// UIKit has started, and a web view made then has touch handlers with
    /// nothing to report to, so the first finger on the page aborts the app.
    var webView: WKWebView {
        if let made = madeWebView { return made }
        let made = makeWebView()
        madeWebView = made
        made.load(URLRequest(url: AppConfig.baseURL))
        return made
    }
    /// The page has said hello since its document was loaded.
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var loadedOnce = false
    @ObservationIgnored private var outbox: [[String: Any]] = []
    @ObservationIgnored var downloads: [ObjectIdentifier: URL] = [:]
    @ObservationIgnored private var icons: [String: UIImage] = [:]
    @ObservationIgnored private let auth = AuthSession()
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    /// How much of the screen's bottom the bar takes, bar and home indicator
    /// together (-1 until measured).
    @ObservationIgnored private var barInset: CGFloat = -1
    #if DEBUG
    @ObservationIgnored private var debugScriptRan = false
    #endif

    init(lock: AppLock) {
        self.lock = lock
        let store = UserDefaults.standard
        lang = L10n.lang(store.string(forKey: "trLang"))
        let choice = store.string(forKey: "trThemeChoice")
        scheme = choice == "dark" ? .dark : (choice == "light" ? .light : nil)
        let launch = UIColor(named: "LaunchBackground") ?? .systemBackground
        let accent = UIColor(named: "AccentColor") ?? .label
        if choice == "system" || choice == nil {
            paper = launch
            ink = accent
        } else {
            paper = UIColor(css: store.string(forKey: "trPaper")) ?? launch
            ink = UIColor(css: store.string(forKey: "trInk")) ?? accent
        }
        super.init()
        Reminders.shared.onOpen = { [weak self] go in self?.go(go) }
    }

    // MARK: Loading

    func load(_ url: URL) {
        if !loadedOnce { phase = .loading }
        webView.load(URLRequest(url: url))
    }

    func retry() {
        phase = .loading
        webView.load(URLRequest(url: AppConfig.baseURL))
    }

    /// A new document: it has to say hello again before it is spoken to.
    func documentChanged() {
        ready = false
        loadedOnce = true
        phase = .ready
    }

    func documentFinished() {
        phase = .ready
        // A page that never says hello (the site before it knew about the
        // app) is shown anyway, a moment after it has loaded.
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    func documentFailed(_ error: Error) {
        let code = (error as NSError).code
        let domain = (error as NSError).domain
        // A navigation the app stopped itself (a link sent to the browser, a
        // download) is not a failure.
        if domain == NSURLErrorDomain && code == NSURLErrorCancelled { return }
        if domain == WKError.errorDomain && code == 102 { return }
        if !loadedOnce {
            phase = .offline
            reveal()
        }
    }

    func reveal() {
        guard !shown else { return }
        withAnimation(.easeOut(duration: 0.2)) { shown = true }
    }

    // MARK: The page's messages

    func handle(_ type: String, _ data: [String: Any]) {
        switch type {
        case "hello":
            ready = true
            if let theme = data["theme"] as? [String: Any] { applyTheme(theme) }
            applyLang(data["lang"] as? String)
            setTabs(data["tabs"] as? [[String: Any]] ?? [], active: data["active"] as? String)
            barHidden = data["barHidden"] as? Bool ?? false
            reveal()
            flush()
            sendSettings()
            sendInsets()
            #if DEBUG
            // `-TRRunJS "<script>"` after the launch runs a line of the page's
            // script once the page is up (e.g. `enterGuestMode()`), for trying
            // the app on a simulator without typing into it.
            if !debugScriptRan, let script = UserDefaults.standard.string(forKey: "TRRunJS"), !script.isEmpty {
                debugScriptRan = true
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
            #endif
        case "tabs":
            setTabs(data["tabs"] as? [[String: Any]] ?? [], active: data["active"] as? String)
        case "tab":
            if let key = data["key"] as? String, tabs.contains(where: { $0.key == key }), key != selected {
                selected = key
            }
        case "theme":
            applyTheme(data)
        case "lang":
            applyLang(data["lang"] as? String)
        case "chrome":
            let hide = data["barHidden"] as? Bool ?? false
            if hide != barHidden { barHidden = hide }
        case "haptic":
            Haptics.play(data["style"] as? String ?? "light")
        case "oauth":
            startSignIn(data)
        case "reminders":
            Reminders.shared.sync(data["items"] as? [[String: Any]] ?? [], ask: data["ask"] as? Bool ?? false)
        case "today":
            saveSnapshot(data)
        case "badge":
            let count = max(0, (data["n"] as? NSNumber)?.intValue ?? 0)
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        case "settings":
            sendSettings()
        case "setLock":
            setLock(data["on"] as? Bool ?? false)
        case "askNotifications":
            askNotifications()
        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case "share":
            if let text = data["url"] as? String, let url = URL(string: text) { ExternalLinks.share([url]) }
        case "print":
            printPage(name: data["name"] as? String)
        default:
            break
        }
    }

    /// Something for the page: `trackerShell.receive({type, data})`. Before the
    /// page has said hello only what still matters later is kept.
    func send(_ type: String, _ data: [String: Any] = [:]) {
        let message: [String: Any] = ["type": type, "data": data]
        guard ready, let webView = madeWebView else {
            if type == "go" || type == "oauthCancel" {
                outbox.append(message)
                if outbox.count > 8 { outbox.removeFirst() }
            }
            return
        }
        webView.callAsyncJavaScript(
            "if (window.trackerShell && typeof window.trackerShell.receive === 'function') window.trackerShell.receive(m);",
            arguments: ["m": message],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    private func flush() {
        let waiting = outbox
        outbox.removeAll()
        for message in waiting {
            send(message["type"] as? String ?? "", message["data"] as? [String: Any] ?? [:])
        }
    }

    // MARK: The bar

    /// The room the bar takes, measured while it is showing (hidden, the
    /// number would only be the home indicator, and the page keeps its room
    /// for when the bar comes back).
    func setBarInset(_ value: CGFloat) {
        guard !barHidden, value >= 0, abs(value - barInset) > 0.5 else { return }
        barInset = value
        sendInsets()
    }

    private func sendInsets() {
        guard barInset >= 0 else { return }
        send("insets", ["bar": Double(barInset)])
    }

    /// The page's "Save as PDF": a web view in an app has no window.print, so
    /// the page asks for the phone's print sheet (which has Save to Files).
    private func printPage(name: String?) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = (name?.isEmpty == false) ? name! : "kristoffergt"
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true) { [weak self] _, _, _ in
            self?.send("printed")
        }
    }

    /// A tab pressed in the bar. The one already open again: the page goes
    /// back to its top.
    func pick(_ key: String) {
        if key == selected {
            send("reselect", ["key": key])
        } else {
            selected = key
            send("tab", ["key": key])
        }
    }

    private func setTabs(_ list: [[String: Any]], active: String?) {
        var next: [ShellTab] = []
        for item in list {
            guard let key = item["key"] as? String, !key.isEmpty, !next.contains(where: { $0.key == key }) else { continue }
            let template = item["template"] as? Bool ?? true
            let icon = item["icon"] as? String
            let iconOn = item["iconOn"] as? String
            next.append(ShellTab(
                key: key,
                label: item["label"] as? String ?? key,
                icon: image(icon, template: template),
                iconOn: image(iconOn, template: template),
                iconID: "\(template)|\(icon?.hashValue ?? 0)|\(iconOn?.hashValue ?? 0)"
            ))
        }
        if next != tabs { tabs = next }
        // No tabs, no bar: nothing at the bottom for the page to keep clear of.
        if next.isEmpty && barInset != 0 {
            barInset = 0
            sendInsets()
        }
        if let active, next.contains(where: { $0.key == active }) {
            if selected != active { selected = active }
        } else if !next.contains(where: { $0.key == selected }) {
            selected = next.first?.key ?? ""
        }
    }

    /// A PNG data URL from the page, fitted into the bar's 25 point square.
    private func image(_ dataURL: String?, template: Bool) -> UIImage? {
        guard let dataURL, !dataURL.isEmpty else { return nil }
        let cacheKey = (template ? "t" : "o") + dataURL
        if let hit = icons[cacheKey] { return hit }
        guard dataURL.hasPrefix("data:image/"),
              let comma = dataURL.firstIndex(of: ","),
              dataURL[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let source = UIImage(data: data)
        else { return nil }
        let side: CGFloat = 25
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let size = source.size
            let scale = min(side / max(size.width, 1), side / max(size.height, 1))
            let width = size.width * scale, height = size.height * scale
            source.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
        }
        let result = drawn.withRenderingMode(template ? .alwaysTemplate : .alwaysOriginal)
        if icons.count > 40 { icons.removeAll() }
        icons[cacheKey] = result
        return result
    }

    // MARK: Theme and language

    /// `{choice: light|dark|system, paper, ink}` from the page's theme switch.
    /// "system" leaves the phone in charge, so the page's own follow-the-phone
    /// switch keeps working inside the app.
    private func applyTheme(_ data: [String: Any]) {
        let choice = data["choice"] as? String ?? ((data["dark"] as? Bool ?? false) ? "dark" : "light")
        let next: ColorScheme? = choice == "system" ? nil : (choice == "dark" ? .dark : .light)
        if scheme != next { scheme = next }
        if let color = UIColor(css: data["paper"] as? String) { paper = color }
        if let color = UIColor(css: data["ink"] as? String) { ink = color }
        madeWebView?.underPageBackgroundColor = paper
        let store = UserDefaults.standard
        store.set(choice, forKey: "trThemeChoice")
        store.set(data["paper"] as? String, forKey: "trPaper")
        store.set(data["ink"] as? String, forKey: "trInk")
    }

    private func applyLang(_ code: String?) {
        guard let code else { return }
        let next = L10n.lang(code)
        if next != lang { lang = next }
        UserDefaults.standard.set(next, forKey: "trLang")
    }

    // MARK: Sign-in

    /// Google will not sign in inside an app's web view, so the page asks
    /// Supabase for the provider's address and hands it over; the round trip
    /// runs in the system's sign-in sheet, with Safari's sign-ins.
    private func startSignIn(_ data: [String: Any]) {
        guard let text = data["url"] as? String, let url = URL(string: text), url.scheme?.lowercased() == "https" else { return }
        auth.start(url: url) { [weak self] callback in
            guard let self else { return }
            if let callback {
                self.finishSignIn(callback)
            } else {
                self.send("oauthCancel")
            }
        }
    }

    /// `kristoffergt://auth?query#fragment` (passed on by the site's
    /// app-auth.html) becomes the app's page again with the same query and
    /// fragment, loaded afresh: the page then finishes the sign-in exactly as
    /// it does on the web, where supabase-js reads its tokens from the address
    /// as it starts, and the page reads an error the same way.
    private func finishSignIn(_ callback: URL) {
        guard var page = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false) else { return }
        let back = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        var items = (back?.queryItems ?? []).filter { $0.name != "app" }
        // A query of its own, different every time, so this is a new document
        // and not a jump to an anchor in the one already open.
        items.insert(URLQueryItem(name: "app", value: String(Int(Date().timeIntervalSince1970))), at: 0)
        page.queryItems = items
        page.percentEncodedFragment = back?.percentEncodedFragment
        if page.path.isEmpty { page.path = "/" }
        if let url = page.url { load(url) }
    }

    // MARK: Links into the app

    /// kristoffergt://go?go=todos (a reminder, a widget) or an address on the
    /// site. kristoffergt://auth is only ever taken by the sign-in sheet: one
    /// arriving from anywhere else is ignored, so no link can sign the app
    /// into somebody else's account.
    func open(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == AppConfig.scheme {
            if url.host?.lowercased() == "go" {
                go(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? "")
            }
            return
        }
        if AppConfig.isAppDocument(url) {
            load(url)
        } else if AppConfig.isOwn(url) {
            ExternalLinks.showInApp(url)
        }
    }

    /// A query the page's start-up links understand (go=todos,
    /// go=calendar&date=..., notif=...).
    func go(_ query: String) {
        guard !query.isEmpty else { return }
        send("go", ["query": query])
    }

    func becameActive() {
        send("resume")
        sendSettings()
    }

    // MARK: Widgets

    private func saveSnapshot(_ data: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(data),
              let json = try? JSONSerialization.data(withJSONObject: data),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: json)
        else { return }
        if SharedStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: The page's "iPhone app" settings

    func sendSettings() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = "on"
            case .denied: status = "off"
            default: status = "ask"
            }
            send("settings", [
                "lock": lock.enabled,
                "lockKind": lock.kind,
                "notifications": status,
                "version": "\(AppConfig.version) (\(AppConfig.build))",
                "widgets": SharedStore.defaults != nil,
            ])
        }
    }

    private func setLock(_ on: Bool) {
        Task {
            if on {
                if await lock.authenticate(reason: L10n.t("lockReason", lang)) { lock.enabled = true }
            } else {
                lock.enabled = false
            }
            sendSettings()
        }
    }

    private func askNotifications() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            sendSettings()
            send("resync")
        }
    }
}

extension UIColor {
    convenience init?(css: String?) {
        guard let rgba = CSSColor.parse(css) else { return nil }
        self.init(red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
    }
}

/// The page's messages, from its own main frame only. The handler is held
/// weakly: the web view's content controller keeps it alive otherwise.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var shell: Shell?

    init(_ shell: Shell) {
        self.shell = shell
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              AppConfig.isOwnHost(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else { return }
        shell?.handle(type, body["data"] as? [String: Any] ?? [:])
    }
}
