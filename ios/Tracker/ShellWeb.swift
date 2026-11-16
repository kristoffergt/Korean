import UIKit
import WebKit

extension Shell {
    func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // The page can tell it is in the app (and still reads as an iPhone).
        configuration.applicationNameForUserAgent = "Mobile/15E148 TrackerApp/\(AppConfig.version)"
        configuration.allowsInlineMediaPlayback = true
        // A video the reader pressed play on starts at once (the page only
        // loads a player after a press).
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.limitsNavigationsToAppBoundDomains = AppConfig.appBound
        // No phone numbers or dates turned into links inside notes.
        configuration.dataDetectorTypes = []

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: BridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakScriptHandler(self), name: BridgeScript.handlerName)
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // The page has its own back gesture (its navigation stack).
        webView.allowsBackForwardNavigationGestures = false
        // The page places itself around the notch, the home indicator and the
        // bar (viewport-fit=cover and env(safe-area-inset-*)).
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.underPageBackgroundColor = paper
        #if DEBUG
        // Safari > Develop on the Mac can inspect the page.
        webView.isInspectable = true
        #endif
        return webView
    }
}

// MARK: - Navigation

extension Shell: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if navigationAction.shouldPerformDownload { return decisionHandler(.download) }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == AppConfig.scheme {
            open(url)
            return decisionHandler(.cancel)
        }
        if ["about", "blob", "data", "javascript"].contains(scheme) { return decisionHandler(.allow) }
        // tel:, mailto:, sms:, maps: and other apps' own addresses.
        if scheme != "http" && scheme != "https" {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        // Frames inside the page (a video player) load where they are.
        if let frame = navigationAction.targetFrame, !frame.isMainFrame { return decisionHandler(.allow) }
        // The app itself stays; the site's other pages (privacy, the resumes,
        // a file link) and every other site open in the app's browser.
        if AppConfig.isAppDocument(url) { return decisionHandler(.allow) }
        if navigationAction.targetFrame == nil {
            // A new window: createWebViewWith decides.
            return decisionHandler(.allow)
        }
        ExternalLinks.open(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        documentChanged()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        documentFinished()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        documentFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        documentFailed(error)
    }

    /// iOS ended the page's process (memory, mostly): load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let url = webView.url, AppConfig.isAppDocument(url) {
            webView.reload()
        } else {
            load(AppConfig.baseURL)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - Downloads

/// A file the page saves (a CSV, a calendar export, a note as Word) goes to
/// a folder of its own in the app's temporary space and from there to the
/// share sheet, where it can be saved to Files or sent on.
extension Shell: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return completionHandler(nil)
        }
        let destination = folder.appendingPathComponent(Self.safeFilename(suggestedFilename))
        downloads[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        ExternalLinks.share([file])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = downloads.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    /// The name the page suggested, kept to one plain file name.
    static func safeFilename(_ suggested: String) -> String {
        let last = (suggested as NSString).lastPathComponent
        let cleaned = last
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\u{0}"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { return "download" }
        return String(cleaned.prefix(120))
    }
}

// MARK: - The page's windows and dialogs

extension Shell: WKUIDelegate {
    /// `window.open` and `target=_blank`: the app itself loads here, a blob
    /// (a guest's own file) is saved, anything else opens in the browser.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" else {
            return nil
        }
        switch url.scheme?.lowercased() ?? "" {
        case "blob", "data":
            webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
                download.delegate = self
            }
        case "http", "https":
            if AppConfig.isAppDocument(url) {
                webView.load(URLRequest(url: url))
            } else {
                ExternalLinks.open(url)
            }
        default:
            UIApplication.shared.open(url)
        }
        return nil
    }

    /// Holding a link to another site: Open (the app's browser), Open in
    /// Safari, Copy link, Share. A link inside the app has no menu: there a
    /// press is a press (and a long press moves things).
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
    ) {
        guard let url = elementInfo.linkURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !AppConfig.isAppDocument(url)
        else { return completionHandler(nil) }
        let lang = self.lang
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: url.host ?? "", children: [
                UIAction(title: L10n.t("open", lang), image: UIImage(systemName: "arrow.up.right.square")) { _ in
                    ExternalLinks.open(url)
                },
                UIAction(title: L10n.t("openInSafari", lang), image: UIImage(systemName: "safari")) { _ in
                    UIApplication.shared.open(url)
                },
                UIAction(title: L10n.t("copyLink", lang), image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = url
                },
                UIAction(title: L10n.t("share", lang), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    ExternalLinks.share([url])
                },
            ])
        }
        completionHandler(configuration)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("ok", lang), style: .default) { _ in completionHandler() })
        present(alert) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("cancel", lang), style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: L10n.t("ok", lang), style: .default) { _ in completionHandler(true) })
        present(alert) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in field.text = defaultText }
        alert.addAction(UIAlertAction(title: L10n.t("cancel", lang), style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: L10n.t("ok", lang), style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        present(alert) { completionHandler(nil) }
    }

    /// Shows a dialog over whatever is on top; with nothing to show it on,
    /// the page gets its answer at once (it is waiting for one).
    private func present(_ alert: UIAlertController, otherwise: () -> Void) {
        guard let top = Presenter.top else { return otherwise() }
        top.present(alert, animated: true)
    }
}
