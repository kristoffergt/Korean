import AuthenticationServices
import UIKit

/// Signing in with Google in the system's sign-in sheet (Google refuses its
/// sign-in inside an app's web view). The sheet ends on the site's
/// app-auth.html, which passes everything Supabase gave it on to
/// kristoffergt://auth; that closes the sheet and hands the address back here.
final class AuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// `completion` gets the kristoffergt://auth address, or nil when the
    /// reader closed the sheet.
    func start(url: URL, completion: @escaping (URL?) -> Void) {
        session?.cancel()
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(AppConfig.scheme)) { callback, _ in
            DispatchQueue.main.async { completion(callback) }
        }
        session.presentationContextProvider = self
        // Safari's own sign-ins (a Google account already signed in) count.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        if !session.start() { completion(nil) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Presenter.window ?? ASPresentationAnchor()
    }
}
