import Foundation
import UserNotifications

/// Reminders scheduled on the phone itself. The page sends every reminder
/// still to come (to-dos, app-thread reminders, calendar events) whenever
/// they change; this keeps the phone's list the same, without touching what
/// is already right. iOS holds 64 at a time, so the 60 soonest are kept and
/// the rest follow as those go off and the page sends the list again.
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    private static let prefix = "tr."
    private static let limit = 60

    /// What a pressed reminder opens (a query the page understands). One
    /// pressed before the app was ready waits here.
    var onOpen: ((String) -> Void)? {
        didSet {
            if let waiting, let onOpen {
                self.waiting = nil
                onOpen(waiting)
            }
        }
    }
    private var waiting: String?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    private struct Item {
        let id: String
        let title: String
        let body: String
        let at: Double
        let go: String

        var signature: String { "\(Int(at))|\(title)|\(body)|\(go)" }
    }

    /// `items`: [{id, title, body, at (ms since 1970), go}]. `ask`: the page
    /// says the reader just set a reminder, which is the moment to ask for
    /// permission if it has never been asked.
    func sync(_ items: [[String: Any]], ask: Bool) {
        let now = Date().timeIntervalSince1970 * 1000
        var wanted: [Item] = []
        for item in items {
            guard let id = item["id"] as? String, !id.isEmpty,
                  let at = (item["at"] as? NSNumber)?.doubleValue, at > now + 1000
            else { continue }
            let title = item["title"] as? String ?? ""
            guard !title.isEmpty else { continue }
            wanted.append(Item(id: id, title: title, body: item["body"] as? String ?? "", at: at, go: item["go"] as? String ?? ""))
        }
        wanted.sort { $0.at < $1.at }
        if wanted.count > Self.limit { wanted = Array(wanted.prefix(Self.limit)) }

        Task {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined, ask, !wanted.isEmpty {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }

            var scheduled: [String: String] = [:]
            for request in await center.pendingNotificationRequests() where request.identifier.hasPrefix(Self.prefix) {
                scheduled[request.identifier] = request.content.userInfo["sig"] as? String ?? ""
            }
            var keep = Set<String>()
            for item in wanted {
                let identifier = Self.prefix + item.id
                keep.insert(identifier)
                if scheduled[identifier] == item.signature { continue }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.threadIdentifier = "reminders"
                content.userInfo = ["sig": item.signature, "go": item.go]
                let moment = Date(timeIntervalSince1970: item.at / 1000)
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
            let stale = scheduled.keys.filter { !keep.contains($0) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(stale))
            }
        }
    }

    private func deliver(_ go: String) {
        if let onOpen {
            onOpen(go)
        } else {
            waiting = go
        }
    }

    /// A reminder going off while the app is open still shows.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let go = response.notification.request.content.userInfo["go"] as? String ?? ""
        await MainActor.run { Reminders.shared.deliver(go) }
    }
}
