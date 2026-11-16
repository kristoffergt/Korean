import Foundation

/// The page's way to the app, put on every page of the site before its own
/// scripts run. The page posts with `trackerNative.post(type, data)` and the
/// app answers through `window.trackerShell.receive({type, data})`, which the
/// page defines. Outside the app neither exists, and the page behaves as the
/// website it is.
enum BridgeScript {
    static let handlerName = "tracker"

    static var source: String {
        """
        (function () {
          if (window.trackerNative) return;
          var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName);
          if (!handler) return;
          function post(type, data) {
            try {
              handler.postMessage({ type: String(type), data: data == null ? {} : JSON.parse(JSON.stringify(data)) });
            } catch (e) {}
          }
          Object.defineProperty(window, 'trackerNative', {
            value: Object.freeze({ platform: 'ios', version: \(AppConfig.bridgeVersion), app: '\(AppConfig.version)', post: post }),
            configurable: false,
            writable: false
          });
        })();
        """
    }
}
