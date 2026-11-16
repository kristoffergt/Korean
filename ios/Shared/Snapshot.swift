import Foundation
import SwiftUI

/// What the page hands the widgets (`trackerNative.post('today', ...)`):
/// the reader's own calendar and to-dos over a stretch of days around today,
/// so a widget can move on to tomorrow by itself at midnight without the app
/// having been opened. Written by the app into the App Group, read by the
/// widget extension. Short keys: it is stored on every change.
struct Snapshot: Codable, Equatable {
    /// Format version, so an older widget can ignore a newer shape.
    var v: Int = 1
    /// The page's language: en, ko or vi.
    var lang: String = "en"
    /// When the page wrote it (ms since 1970).
    var made: Double = 0
    /// The days it covers, YYYY-MM-DD, both ends included.
    var from: String = ""
    var to: String = ""
    /// The calendar's first weekday: 0 Sunday, 1 Monday.
    var weekStart: Int = 0
    var events: [Event] = []
    var todos: [Todo] = []
    /// Hours studied per day (YYYY-MM-DD), the last week or so.
    var study: [String: Double] = [:]
    /// The daily study goal, in hours.
    var goal: Double = 0
    /// False for a guest or a signed-out page: the widgets say to sign in.
    var signedIn: Bool = false

    struct Event: Codable, Equatable, Hashable, Identifiable {
        /// The event's id plus the day the occurrence starts: one per occurrence.
        var id: String
        var t: String
        /// First day, YYYY-MM-DD.
        var d: String
        /// Days it runs on after the first (0 for a one-day event).
        var n: Int = 0
        /// Start and end time, HH:mm; no start = all day.
        var s: String?
        var f: String?
        /// Its colour, #RRGGBB.
        var c: String?
    }

    struct Todo: Codable, Equatable, Hashable, Identifiable {
        var id: String
        var t: String
        /// The day it is due (scope "day"), or the first day of its week,
        /// month or year.
        var d: String?
        /// day, week, month or year; nil for one with no date.
        var sc: String?
        /// Time, HH:mm.
        var s: String?
        /// Done, and on which day it was done.
        var x: Bool = false
        var xd: String?
        /// Its course's colour, #RRGGBB.
        var c: String?
    }
}

// Missing keys take the defaults above (the synthesized decoder would refuse
// the whole snapshot over one), so the page can leave out what is empty.
extension Snapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        lang = try c.decodeIfPresent(String.self, forKey: .lang) ?? "en"
        made = try c.decodeIfPresent(Double.self, forKey: .made) ?? 0
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        weekStart = try c.decodeIfPresent(Int.self, forKey: .weekStart) ?? 0
        events = try c.decodeIfPresent([Event].self, forKey: .events) ?? []
        todos = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        study = try c.decodeIfPresent([String: Double].self, forKey: .study) ?? [:]
        goal = try c.decodeIfPresent(Double.self, forKey: .goal) ?? 0
        signedIn = try c.decodeIfPresent(Bool.self, forKey: .signedIn) ?? false
    }
}

extension Snapshot.Event {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        d = try c.decode(String.self, forKey: .d)
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 0
        s = try c.decodeIfPresent(String.self, forKey: .s)
        f = try c.decodeIfPresent(String.self, forKey: .f)
        self.c = try c.decodeIfPresent(String.self, forKey: .c)
    }
}

extension Snapshot.Todo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        d = try c.decodeIfPresent(String.self, forKey: .d)
        sc = try c.decodeIfPresent(String.self, forKey: .sc)
        s = try c.decodeIfPresent(String.self, forKey: .s)
        x = try c.decodeIfPresent(Bool.self, forKey: .x) ?? false
        xd = try c.decodeIfPresent(String.self, forKey: .xd)
        self.c = try c.decodeIfPresent(String.self, forKey: .c)
    }
}

/// The App Group both targets share.
enum SharedStore {
    static let key = "snapshot.v1"

    static var group: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TRAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    /// nil when the App Group is not provisioned (a build without a team):
    /// the app then carries on without widgets rather than writing somewhere
    /// the widget cannot read.
    static var defaults: UserDefaults? {
        guard let group,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
        else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func load() -> Snapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// True when it was different from what was stored (only then are the
    /// widgets asked to redraw).
    @discardableResult
    static func save(_ snapshot: Snapshot) -> Bool {
        guard let defaults else { return false }
        var old = load()
        old?.made = snapshot.made
        if old == snapshot { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// Days as the page writes them (YYYY-MM-DD, the phone's own time zone).
enum DayKey {
    static func of(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func add(_ key: String, days: Int, calendar: Calendar = .current) -> String {
        guard let date = date(key, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return of(next, calendar: calendar)
    }

    static func diff(_ from: String, _ to: String, calendar: Calendar = .current) -> Int {
        guard let a = date(from, calendar: calendar), let b = date(to, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

extension Color {
    /// #RGB, #RRGGBB, rgb(r, g, b) or rgba(r, g, b, a).
    init?(css: String?) {
        guard let rgba = CSSColor.parse(css) else { return nil }
        self.init(.sRGB, red: rgba.0, green: rgba.1, blue: rgba.2, opacity: rgba.3)
    }
}

enum CSSColor {
    static func parse(_ value: String?) -> (Double, Double, Double, Double)? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        if text.hasPrefix("#") {
            text.removeFirst()
            if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
            guard text.count == 6 || text.count == 8, let number = UInt64(text, radix: 16) else { return nil }
            if text.count == 8 {
                return (Double((number >> 24) & 0xFF) / 255, Double((number >> 16) & 0xFF) / 255,
                        Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
            }
            return (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255,
                    Double(number & 0xFF) / 255, 1)
        }
        if text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") {
            let numbers = text[text.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count >= 3 else { return nil }
            return (numbers[0] / 255, numbers[1] / 255, numbers[2] / 255, numbers.count > 3 ? numbers[3] : 1)
        }
        return nil
    }
}
