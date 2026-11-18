import SwiftUI
import WidgetKit

/// Shows the content once the app has written the page's data for a
/// signed-in reader; otherwise says what to do.
struct Gate<Content: View>: View {
    let snapshot: Snapshot?
    @ViewBuilder let content: (Snapshot) -> Content

    var body: some View {
        if let snapshot, snapshot.signedIn {
            content(snapshot)
        } else {
            EmptyNote(text: L10n.t(snapshot == nil ? "openApp" : "signIn", snapshot?.lang ?? L10n.lang(nil)))
        }
    }
}

// MARK: - A day as the calendar draws it

/// One day of the week or the five weeks: its number in the middle (today
/// in a celadon circle, a past day greyed), the day's events as chips, and
/// its to-dos as one chip counting how many are done, so a day with
/// something left is easy to see.
struct DayCell: View {
    let snapshot: Snapshot
    let day: String
    let today: String
    /// The weekday over the number (the week's columns); nil for the five
    /// weeks, which name the weekdays once above.
    let weekday: String?
    let chips: Int
    var dim = false
    /// False for a calendar set to show events only.
    var todos = true

    var body: some View {
        let isToday = day == today
        let events = snapshot.items(on: day, todos: false)
        let tally = todos ? snapshot.todoTally(on: day) : nil
        let room = max(0, chips - (tally == nil ? 0 : 1))
        let shown = events.count > room ? Array(events.prefix(max(0, room - 1))) : events
        let extra = events.count - shown.count
        let size: CGFloat = weekday == nil ? 11 : 13
        VStack(alignment: .center, spacing: 2) {
            if let weekday {
                Text(weekday)
                    .font(Typo.text(9, .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
            Text(number)
                .font(Typo.number(size, isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : (day < today ? Palette.inkSoft : Palette.ink))
                .lineLimit(1)
                .frame(width: size * 1.75, height: size * 1.75)
                .background {
                    if isToday { Circle().fill(Palette.celadon).widgetAccentable() }
                }
            ForEach(shown) { item in
                EventChip(title: item.title, color: item.color,
                          continuesIn: item.continuesIn && day != weekFirst,
                          continuesOut: item.continuesOut, size: 9)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(Typo.number(8.5, .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if let tally {
                TodoBunchChip(done: tally.done, total: tally.total, size: 9)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(dim ? 0.55 : 1)
    }

    private var number: String {
        guard let date = DayKey.date(day) else { return "" }
        return String(Calendar.current.component(.day, from: date))
    }

    /// A longer event starts again with its title on each row's first day.
    private var weekFirst: String {
        Clock.weekStart(of: day, first: snapshot.weekStart)
    }
}

// MARK: - Week

struct WeekView: View {
    let entry: DayEntry
    var todos = true

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            let start = Clock.weekStart(of: today, first: snapshot.weekStart)
            let names = Clock.weekdays(lang: snapshot.lang, first: snapshot.weekStart)
            GeometryReader { geo in
                // Weekday and number take about 38 points; a chip and its
                // gap 16.
                let chips = max(1, Int((geo.size.height - 38) / 16))
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        let day = DayKey.add(start, days: index)
                        Link(destination: WidgetLink.calendar(day)) {
                            DayCell(snapshot: snapshot, day: day, today: today, weekday: names[index], chips: chips, todos: todos)
                        }
                    }
                }
            }
        }
        .widgetURL(WidgetLink.calendar(DayKey.of(entry.date), week: true))
    }
}

// MARK: - Five weeks

struct MonthView: View {
    let entry: DayEntry
    var todos = true

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            let start = DayKey.add(Clock.weekStart(of: today, first: snapshot.weekStart), days: -7)
            let end = DayKey.add(start, days: 34)
            let names = Clock.weekdays(lang: snapshot.lang, first: snapshot.weekStart)
            let month = DayKey.date(today).map { Calendar.current.component(.month, from: $0) } ?? 0
            GeometryReader { geo in
                let head: CGFloat = 36
                let rowHeight = max(30, (geo.size.height - head - 12) / 5)
                // The number takes about 21 points; a chip and its gap 16.
                let chips = max(1, Int((rowHeight - 21) / 16))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(range(start, end, lang: snapshot.lang))
                            .font(Typo.heading(14))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        TodayTag(lang: snapshot.lang)
                    }
                    .frame(height: 20)
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(names[index])
                                .font(Typo.text(9, .semibold))
                                .foregroundStyle(Palette.inkSoft)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 13)
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { column in
                                let day = DayKey.add(start, days: row * 7 + column)
                                let other = DayKey.date(day).map { Calendar.current.component(.month, from: $0) != month } ?? false
                                Link(destination: WidgetLink.calendar(day)) {
                                    DayCell(snapshot: snapshot, day: day, today: today, weekday: nil, chips: chips, dim: other && day < today, todos: todos)
                                }
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .widgetURL(WidgetLink.calendar(DayKey.of(entry.date), week: true))
    }

    private func range(_ start: String, _ end: String, lang: String) -> String {
        let a = Clock.shortDate(start, lang: lang) ?? start
        let b = Clock.shortDate(end, lang: lang) ?? end
        return "\(a) \u{2013} \(b)"
    }
}

// MARK: - Day

struct DayView: View {
    let entry: DayEntry
    var todos = true
    var done = true
    /// Drawn outside a widget (the lock screen picture): the size to draw as.
    var size: WidgetFamily?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            let items = snapshot.items(on: today, todos: todos, done: done)
            let open = items.filter { !$0.done }.count
            GeometryReader { geo in
                let rowHeight: CGFloat = (size ?? family) == .systemLarge ? 22 : 19
                let fit = max(1, Int((geo.size.height - 28) / rowHeight))
                let shown = items.count > fit ? Array(items.prefix(fit - 1)) : items
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(Clock.format(entry.date, template: "EEEEdMMM", lang: snapshot.lang))
                            .font(Typo.heading(15))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if open > 0 { CountPill(count: open) }
                    }
                    .frame(height: 22)
                    .padding(.bottom, 4)
                    if items.isEmpty {
                        EmptyNote(text: L10n.t("nothingToday", snapshot.lang))
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            if index > 0, startsLoose(shown, index) {
                                Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 3)
                            }
                            AgendaRow(item: item, lang: snapshot.lang)
                                .frame(height: rowHeight)
                        }
                        if items.count > shown.count {
                            MoreLine(count: items.count - shown.count, lang: snapshot.lang)
                                .padding(.leading, timeWidth(snapshot.lang) + 7)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .widgetURL(WidgetLink.calendar(DayKey.of(entry.date)))
    }

    /// The to-dos with no time come after a hairline, under everything else.
    private func startsLoose(_ items: [DayItem], _ index: Int) -> Bool {
        let item = items[index], before = items[index - 1]
        return item.kind == .todo && item.time == nil && !(before.kind == .todo && before.time == nil)
    }
}

func timeWidth(_ lang: String) -> CGFloat { lang == "en" ? 54 : 40 }

/// A row of the day: time (or "all day"), the event's colour or the to-do's
/// box, the title, and an event's end.
struct AgendaRow: View {
    let item: DayItem
    let lang: String

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let time = item.time {
                    Text(Clock.time(time, lang: lang)).font(Typo.number(11, .medium))
                } else if item.kind == .event {
                    Text(L10n.t("allDay", lang)).font(Typo.text(9.5, .medium))
                } else {
                    Text(" ").font(Typo.text(9.5))
                }
            }
            .foregroundStyle(Palette.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: timeWidth(lang), alignment: .trailing)
            if item.kind == .event {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(ChipColors(item.color).fill)
                    .frame(width: 3, height: 15)
                    .widgetAccentable()
            } else {
                TodoBox(done: item.done, size: 13)
            }
            Text(item.title)
                .font(Typo.text(13, .medium))
                .foregroundStyle(item.done ? Palette.inkSoft : Palette.ink)
                .strikethrough(item.done, color: Palette.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let end = item.end {
                Text("\u{2013}\(Clock.time(end, lang: lang))")
                    .font(Typo.number(10.5))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Up next

struct UpNextView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            switch family {
            case .accessoryInline:
                inline(snapshot)
            case .accessoryRectangular:
                rectangular(snapshot)
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    MiniMonth(snapshot: snapshot, now: entry.date)
                        .frame(width: 136)
                    Rectangle().fill(Palette.line).frame(width: 1)
                    UpNextList(snapshot: snapshot, now: entry.date, limit: 5)
                }
            default:
                UpNextList(snapshot: snapshot, now: entry.date, limit: 4)
            }
        }
        .widgetURL(WidgetLink.todos())
    }

    private func next(_ snapshot: Snapshot) -> Upcoming? {
        snapshot.upcoming(from: entry.date, limit: 1).first
    }

    private func when(_ pair: Upcoming, lang: String) -> String {
        let today = DayKey.of(entry.date)
        if pair.day == today, let time = pair.item.time { return Clock.time(time, lang: lang) }
        if pair.day == today { return L10n.t("today", lang) }
        return Clock.shortDate(pair.day, lang: lang) ?? ""
    }

    @ViewBuilder private func inline(_ snapshot: Snapshot) -> some View {
        if let pair = next(snapshot) {
            Text("\(when(pair, lang: snapshot.lang)) \u{00B7} \(pair.item.title)")
        } else {
            Text(L10n.t("nothingNext", snapshot.lang))
        }
    }

    @ViewBuilder private func rectangular(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L10n.t("upcoming", snapshot.lang))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let pair = next(snapshot) {
                Text(pair.item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(when(pair, lang: snapshot.lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.t("nothingNext", snapshot.lang))
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UpNextList: View {
    let snapshot: Snapshot
    let now: Date
    let limit: Int

    var body: some View {
        let today = DayKey.of(now)
        let all = snapshot.upcoming(from: now, limit: limit + 20)
        let shown = Array(all.prefix(limit))
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.t("upcoming", snapshot.lang))
                .font(Typo.heading(13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.bottom, 1)
            if shown.isEmpty {
                EmptyNote(text: L10n.t("nothingNext", snapshot.lang))
            } else {
                ForEach(shown) { pair in
                    HStack(spacing: 6) {
                        if pair.item.kind == .event {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(ChipColors(pair.item.color).fill)
                                .frame(width: 3, height: 13)
                                .widgetAccentable()
                        } else {
                            TodoBox(done: false, size: 12)
                        }
                        Text(pair.item.title)
                            .font(Typo.text(12.5, .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let label = label(pair, today: today) {
                            Text(label)
                                .font(Typo.number(10.5))
                                .foregroundStyle(Palette.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }
                if all.count > shown.count {
                    MoreLine(count: all.count - shown.count, lang: snapshot.lang, size: 10.5)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func label(_ pair: Upcoming, today: String) -> String? {
        if pair.day == today { return pair.item.time.map { Clock.time($0, lang: snapshot.lang) } }
        if pair.day == DayKey.add(today, days: 1) {
            let word = L10n.t("tomorrow", snapshot.lang)
            return pair.item.time.map { "\(word) \(Clock.time($0, lang: snapshot.lang))" } ?? word
        }
        return Clock.shortDate(pair.day, lang: snapshot.lang)
    }
}

/// This month, small: the weekdays, the dates, today in the celadon tag's
/// colour, and dots in the events' colours (the phone month grid's).
struct MiniMonth: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let lang = snapshot.lang
        let calendar = Calendar.current
        let today = DayKey.of(now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let first = DayKey.of(monthStart)
        let length = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let last = DayKey.add(first, days: length - 1)
        let gridStart = Clock.weekStart(of: first, first: snapshot.weekStart)
        let rows = DayKey.diff(gridStart, last) / 7 + 1
        let names = Clock.weekdays(lang: lang, first: snapshot.weekStart)
        let cellHeight: CGFloat = rows > 5 ? 16 : 19
        VStack(alignment: .leading, spacing: 2) {
            Text(Clock.format(now, template: "LLLL", lang: lang).capitalized(with: L10n.locale(lang)))
                .font(Typo.heading(13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.bottom, 1)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(names[index])
                        .font(Typo.text(8, .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = DayKey.add(gridStart, days: row * 7 + column)
                        miniDay(day, inMonth: day >= first && day <= last, isToday: day == today, dots: rows <= 5)
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                    }
                }
            }
        }
    }

    @ViewBuilder private func miniDay(_ day: String, inMonth: Bool, isToday: Bool, dots: Bool) -> some View {
        let number = DayKey.date(day).map { String(Calendar.current.component(.day, from: $0)) } ?? ""
        VStack(spacing: 1) {
            Text(number)
                .font(Typo.number(10, isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : (inMonth ? Palette.ink : Palette.inkSoft.opacity(0.5)))
                .frame(width: 17, height: 14)
                .background {
                    if isToday { Circle().fill(Palette.celadon).widgetAccentable() }
                }
            if dots {
                let colors = snapshot.events(on: day).prefix(3).map { ChipColors($0.color).fill }
                let tally = snapshot.todoTally(on: day)
                HStack(spacing: 1.5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 3, height: 3)
                    }
                    // The day's to-dos: an open box, filled green once all
                    // of them are done.
                    if let tally {
                        let all = tally.done >= tally.total
                        RoundedRectangle(cornerRadius: 0.6)
                            .fill(all ? Palette.on : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 0.6).strokeBorder(all ? Palette.on : Palette.inkSoft, lineWidth: 0.8))
                            .frame(width: 3.2, height: 3.2)
                    }
                }
                .frame(height: 3)
                .opacity(inMonth ? 1 : 0.5)
            }
        }
    }
}
