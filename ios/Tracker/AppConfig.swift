import Foundation

/// Where the app's page lives and which addresses count as its own.
enum AppConfig {
    /// The page the app loads: `TRBaseURL` in Info.plist, from the TR_BASE_URL
    /// build setting (Debug: the Mac's local server in the Simulator, the live
    /// site on a phone; Release: the live site). A launch argument overrides
    /// it, e.g. `-TRBaseURL http://localhost:8765` in the scheme or after
    /// `xcrun simctl launch`.
    static let baseURL: URL = {
        if let arg = UserDefaults.standard.string(forKey: "TRBaseURL"), let url = URL(string: arg), url.scheme != nil {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "TRBaseURL") as? String,
           let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "https://kristoffergt.com/")!
    }()

    /// The app's own URL scheme: sign-in comes back on kristoffergt://auth,
    /// the widget and reminders open kristoffergt://go?to=...
    static let scheme = "kristoffergt"

    static let liveHosts: Set<String> = ["kristoffergt.com", "www.kristoffergt.com"]

    /// Release builds list the live site as the app's bound domains (the
    /// "Info.plist from build settings" phase), which is what lets the site's
    /// service worker run in the app. Such a web view can only navigate to
    /// those domains, so it has to be told.
    static let appBound: Bool = {
        guard let domains = Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String] else { return false }
        return !domains.isEmpty
    }()

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    /// The bridge's version, read by the page as `trackerNative.version`.
    static let bridgeVersion = 1

    /// The site this app belongs to: the loaded host, or the live one.
    static func isOwnHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == baseURL.host?.lowercased() || liveHosts.contains(host)
    }

    static func isOwn(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return isOwnHost(url.host)
    }

    /// The app itself (the root or index.html), as against the site's other
    /// pages (privacy, terms, the resumes, file links), which open in the
    /// app's browser instead of replacing the app.
    static func isAppDocument(_ url: URL) -> Bool {
        guard isOwn(url) else { return false }
        let base = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        let path = url.path.isEmpty ? "/" : url.path
        return path == "/" || path == "/index.html" || path == base || path == base + "index.html"
    }
}
