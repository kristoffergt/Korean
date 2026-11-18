import SwiftUI
import WidgetKit

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

/// The list widget's entry: the day and the list chosen in its settings.
struct ListEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let list: ListKind
}

/// One timeline for every widget but the configurable list: an entry now,
/// one at each of the next week's midnights (so "today" moves on with the
/// phone not opened), and one as each of today's timed things begins (so
/// "Up next" drops what has started). The app asks for a fresh timeline
/// whenever the page's data changes.
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DayEntry) -> Void) {
        let stored = SharedStore.load()
        completion(DayEntry(date: Date(), snapshot: context.isPreview && stored == nil ? .sample : stored))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DayEntry>) -> Void) {
        let snapshot = SharedStore.load()
        let now = Date()
        let dates = Self.moments(from: now, snapshot: snapshot)
        let entries = dates.map { DayEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func moments(from now: Date, snapshot: Snapshot?) -> [Date] {
        let calendar = Calendar.current
        var dates = [now]
        let today = calendar.startOfDay(for: now)
        for days in 1...7 {
            if let midnight = calendar.date(byAdding: .day, value: days, to: today) { dates.append(midnight) }
        }
        if let snapshot {
            let key = DayKey.of(now)
            for item in snapshot.items(on: key) {
                guard let time = item.time, let at = Clock.date(key, time), at > now else { continue }
                dates.append(at)
            }
        }
        return Array(Set(dates)).sorted().prefix(40).map { $0 }
    }
}

// MARK: - A day's things

/// An event or a to-do, as one day shows it.
struct DayItem: Identifiable, Hashable {
    enum Kind { case event, todo }

    let id: String
    let kind: Kind
    let title: String
    /// HH:mm, or nil for all day / no time.
    let time: String?
    let end: String?
    let color: String?
    let done: Bool
    /// For a day of an event that runs over several.
    let continuesIn: Bool
    let continuesOut: Bool
}

extension Snapshot {
    /// The day is inside what the page sent.
    func covers(_ day: String) -> Bool {
        !from.isEmpty && day >= from && day <= to
    }

    func events(on day: String) -> [DayItem] {
        events.compactMap { event in
            let last = DayKey.add(event.d, days: event.n)
            guard day >= event.d && day <= last else { return nil }
            let first = day == event.d
            return DayItem(
                id: "e\(event.id)\(day)",
                kind: .event,
                title: event.t,
                // A later day of a longer event is all day there.
                time: first ? event.s.map(Clock.trim) : nil,
                end: first && event.n == 0 ? event.f.map(Clock.trim) : nil,
                color: event.c,
                done: false,
                continuesIn: !first,
                continuesOut: day != last
            )
        }
    }

    /// To-dos due that day (a day's to-dos, not a week's or a month's).
    func todos(on day: String) -> [DayItem] {
        todos.compactMap { todo in
            guard (todo.sc ?? "day") == "day", todo.d == day else { return nil }
            return DayItem(id: "t\(todo.id)", kind: .todo, title: todo.t, time: todo.s.map(Clock.trim), end: nil,
                           color: todo.c, done: todo.x, continuesIn: false, continuesOut: false)
        }
    }

    /// The day in order: all-day events, then everything with a time, then
    /// to-dos with none. A widget set to leave out to-dos, or the finished
    /// ones, says so.
    func items(on day: String, todos withTodos: Bool = true, done withDone: Bool = true) -> [DayItem] {
        let dayTodos = withTodos ? todos(on: day).filter { withDone || !$0.done } : []
        let all = events(on: day) + dayTodos
        let allDay = all.filter { $0.kind == .event && $0.time == nil }
        let timed = all.filter { $0.time != nil }.sorted { ($0.time ?? "") < ($1.time ?? "") }
        let loose = all.filter { $0.kind == .todo && $0.time == nil }
            .sorted { !$0.done && $1.done }
        return allDay + timed + loose
    }

    /// What is coming: today's to-dos with no time and anything still to
    /// start today, then the next two weeks, earliest first.
    func upcoming(from now: Date, limit: Int) -> [Upcoming] {
        let today = DayKey.of(now)
        let clock = Clock.hm(now)
        var out: [(String, DayItem)] = []
        // Open to-dos from earlier days are still to do.
        for todo in todos where !todo.x && (todo.sc ?? "day") == "day" {
            if let d = todo.d, d < today, covers(d) || d >= DayKey.add(today, days: -30) {
                out.append((d, DayItem(id: "t\(todo.id)", kind: .todo, title: todo.t, time: nil, end: nil,
                                       color: todo.c, done: false, continuesIn: false, continuesOut: false)))
            }
        }
        out.sort { $0.0 < $1.0 }
        var day = today
        for _ in 0..<15 {
            for item in items(on: day) where !item.done && !item.continuesIn {
                if day == today, let time = item.time, time < clock { continue }
                out.append((day, item))
            }
            if out.count >= limit + 6 { break }
            day = DayKey.add(day, days: 1)
        }
        return Array(out.prefix(limit)).map { Upcoming(day: $0.0, item: $0.1) }
    }

    /// A day's to-dos counted for the calendar: how many are done of how
    /// many, nil for a day with none.
    func todoTally(on day: String) -> (done: Int, total: Int)? {
        let mine = todos.filter { ($0.sc ?? "day") == "day" && $0.d == day }
        guard !mine.isEmpty else { return nil }
        return (mine.filter(\.x).count, mine.count)
    }

    func studied(on day: String) -> Double {
        study[day] ?? 0
    }
}

/// One thing still to come and the day it is on.
struct Upcoming: Identifiable {
    let day: String
    let item: DayItem
    var id: String { item.id + day }
}

// MARK: - To-do lists

/// The page's to-do sections, as the list widget offers them.
enum ListKind: String, CaseIterable {
    case today, tomorrow, week, month, year, upcoming

    var titleKey: String {
        switch self {
        case .today: "listToday"
        case .tomorrow: "listTomorrow"
        case .week: "listWeek"
        case .month: "listMonth"
        case .year: "listYear"
        case .upcoming: "listUpcoming"
        }
    }
}

struct ListRow: Identifiable, Hashable {
    let id: String
    let title: String
    /// What stands at the right: a time, or a date.
    let when: String?
    let color: String?
    /// Done in the list's own stretch of time: shown crossed out, under the
    /// open ones.
    var done = false
}

extension Snapshot {
    /// The open to-dos of a list, then the ones finished in its own stretch
    /// of time (today, tomorrow, this week, month or year), crossed out.
    func list(_ kind: ListKind, today: String) -> [ListRow] {
        let open = openList(kind, today: today)
        let done = doneList(kind, today: today).map { todo in
            ListRow(id: todo.id, title: todo.t, when: nil, color: todo.c, done: true)
        }
        return open + done
    }

    private func doneList(_ kind: ListKind, today: String) -> [Todo] {
        let finished = todos.filter(\.x)
        switch kind {
        case .today:
            return finished.filter { ($0.sc ?? "day") == "day" && ($0.d == today || $0.xd == today) }
        case .tomorrow:
            let tomorrow = DayKey.add(today, days: 1)
            return finished.filter { ($0.sc ?? "day") == "day" && $0.d == tomorrow }
        case .week, .month, .year:
            let start: String
            switch kind {
            case .week: start = Clock.weekStart(of: today, first: weekStart)
            case .month: start = String(today.prefix(8)) + "01"
            default: start = String(today.prefix(5)) + "01-01"
            }
            return finished.filter { $0.sc == kind.rawValue && (($0.d ?? "") >= start || ($0.xd ?? "") >= start) }
        case .upcoming:
            return []
        }
    }

    private func openList(_ kind: ListKind, today: String) -> [ListRow] {
        let open = todos.filter { !$0.x }
        func row(_ todo: Todo, showDate: Bool) -> ListRow {
            var when: String?
            if let time = todo.s.map(Clock.trim) {
                when = showDate && todo.d != today ? Clock.shortDate(todo.d, lang: lang) : Clock.time(time, lang: lang)
            } else if showDate, let d = todo.d, d != today {
                when = Clock.shortDate(d, lang: lang)
            }
            return ListRow(id: todo.id, title: todo.t, when: when, color: todo.c)
        }
        switch kind {
        case .today:
            return open
                .filter { ($0.sc ?? "day") == "day" && ($0.d ?? "~") <= today }
                .sorted { ($0.d ?? "", $0.s ?? "99") < ($1.d ?? "", $1.s ?? "99") }
                .map { row($0, showDate: true) }
        case .tomorrow:
            let tomorrow = DayKey.add(today, days: 1)
            return open
                .filter { ($0.sc ?? "day") == "day" && $0.d == tomorrow }
                .sorted { ($0.s ?? "99") < ($1.s ?? "99") }
                .map { row($0, showDate: false) }
        case .week, .month, .year:
            return open
                .filter { $0.sc == kind.rawValue && ($0.d ?? "~") <= today }
                .sorted { ($0.d ?? "") < ($1.d ?? "") }
                .map { row($0, showDate: false) }
        case .upcoming:
            let end = DayKey.add(today, days: 14)
            return open
                .filter { ($0.sc ?? "day") == "day" && ($0.d ?? "") > today && ($0.d ?? "") <= end }
                .sorted { ($0.d ?? "", $0.s ?? "99") < ($1.d ?? "", $1.s ?? "99") }
                .map { row($0, showDate: true) }
        }
    }
}

// MARK: - Times and dates in the page's language

enum Clock {
    nonisolated static func trim(_ time: String) -> String {
        String(time.prefix(5))
    }

    static func hm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func date(_ day: String, _ time: String) -> Date? {
        guard let start = DayKey.date(day) else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: start)
    }

    /// 18:00 in Korean and Vietnamese, 6:00 PM in English (as the page does).
    static func time(_ time: String, lang: String) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return time }
        if lang != "en" { return String(format: "%02d:%02d", parts[0], parts[1]) }
        let hour = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", hour, parts[1], parts[0] < 12 ? "AM" : "PM")
    }

    /// 24 Sep, 9월 24일, 24 thg 9.
    static func shortDate(_ day: String?, lang: String) -> String? {
        guard let day, let date = DayKey.date(day) else { return nil }
        return format(date, template: "dMMM", lang: lang)
    }

    static func format(_ date: Date, template: String, lang: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(lang)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Weekday initials for the calendar's columns, starting on `first`
    /// (0 Sunday).
    static func weekdays(lang: String, first: Int) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale(lang)
        let symbols = (lang == "en" ? formatter.shortWeekdaySymbols : formatter.veryShortWeekdaySymbols) ?? []
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        return (0..<7).map { symbols[($0 + first) % 7] }
    }

    /// 1h 25m, 1시간 25분, 1 giờ 25 phút.
    static func duration(hours: Double, lang: String) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        switch lang {
        case "ko": return h > 0 ? (m > 0 ? "\(h)시간 \(m)분" : "\(h)시간") : "\(m)분"
        case "vi": return h > 0 ? (m > 0 ? "\(h) giờ \(m) phút" : "\(h) giờ") : "\(m) phút"
        default: return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
        }
    }

    /// The first day of the week holding `day`.
    static func weekStart(of day: String, first: Int) -> String {
        guard let date = DayKey.date(day) else { return day }
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return DayKey.add(day, days: -((weekday - first + 7) % 7))
    }
}

// MARK: - Links into the app

enum WidgetLink {
    static func todos() -> URL { URL(string: "kristoffergt://go?go=todos")! }

    static func calendar(_ day: String, week: Bool = false) -> URL {
        URL(string: "kristoffergt://go?go=calendar&date=\(day)\(week ? "&view=week" : "")")!
    }
}

// MARK: - The gallery's picture

extension Snapshot {
    /// Shown in the widget gallery before the app has written anything.
    static var sample: Snapshot {
        let today = DayKey.of(Date())
        var s = Snapshot()
        s.lang = L10n.lang(nil)
        s.signedIn = true
        s.from = DayKey.add(today, days: -14)
        s.to = DayKey.add(today, days: 42)
        s.goal = 3
        s.study = [today: 1.4]
        s.events = [
            Event(id: "1", t: "Korean class", d: today, n: 0, s: "09:00", f: "10:30", c: "#6E8FB0"),
            Event(id: "2", t: "Lunch", d: today, n: 0, s: "12:00", f: "13:00", c: "#7FA694"),
            Event(id: "3", t: "Trip", d: DayKey.add(today, days: 2), n: 2, s: nil, f: nil, c: "#B37B4F"),
            Event(id: "4", t: "Study group", d: DayKey.add(today, days: 1), n: 0, s: "18:30", f: "20:00", c: "#9C7BB0"),
        ]
        s.todos = [
            Todo(id: "a", t: "Reply to the email", d: today, sc: "day", s: nil, x: false, xd: nil, c: nil),
            Todo(id: "b", t: "Pay the bill", d: today, sc: "day", s: "08:40", x: true, xd: today, c: nil),
            Todo(id: "c", t: "Pick up the parcel", d: today, sc: "day", s: "17:30", x: false, xd: nil, c: nil),
            Todo(id: "d", t: "Read ten pages", d: Clock.weekStart(of: today, first: 0), sc: "week", s: nil, x: false, xd: nil, c: nil),
            Todo(id: "e", t: "Plan the weekend", d: DayKey.add(today, days: 3), sc: "day", s: nil, x: false, xd: nil, c: nil),
        ]
        return s
    }
}
