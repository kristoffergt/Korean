import SafariServices
import UIKit

/// The window and the controller on top, for whatever the app presents
/// over the page (alerts, the share sheet, the in-app browser).
enum Presenter {
    static var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    static var top: UIViewController? {
        var controller = window?.rootViewController
        while let next = controller?.presentedViewController, !next.isBeingDismissed {
            controller = next
        }
        return controller
    }

    /// Presents `controller` from the top, anchoring a popover (iPad) to the
    /// middle of the window.
    static func present(_ controller: UIViewController) {
        guard let top else { return }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

/// Links that leave the app's page.
enum ExternalLinks {
    /// Another app first when it claims the address (YouTube, Maps, a bank),
    /// otherwise the app's own browser, so the reader stays in the app.
    static func open(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url)
            return
        }
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            if !opened { showInApp(url) }
        }
    }

    static func showInApp(_ url: URL) {
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .close
        browser.preferredControlTintColor = Presenter.window?.tintColor
        Presenter.present(browser)
    }

    /// A file the page handed over (a download, an export): the share sheet,
    /// from which it can be saved to Files, sent, or opened elsewhere.
    static func share(_ items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        Presenter.present(sheet)
    }
}
