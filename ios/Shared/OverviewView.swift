import SwiftUI
import WidgetKit

/// What the Overview shows, chosen in the widget's settings (hold it, Edit
/// Widget): today's studying, this month, what is coming up and the week,
/// each on or off, and up to two to-do lists side by side.
struct OverviewParts: Equatable {
    var study = true
    var month = true
    var upNext = true
    var week = true
    var lists: [ListKind] = [.week, .month]
}

/// The whole-page widget (iOS 27's extra-large iPhone size, 4 x 6): today
/// and today's studying, this month beside what is coming up (the Up next
/// widget's medium face), the week day by day (the Week widget's cells), and
/// two to-do lists side by side. The parts left out give their room to the
/// rest. Each part opens its own place on the site.
struct OverviewView: View {
    let entry: DayEntry
    var parts = OverviewParts()

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            let lists = Array(parts.lists.prefix(2))
            GeometryReader { geo in
                let room = OverviewRoom(parts: parts, height: geo.size.height)
                VStack(alignment: .leading, spacing: 8) {
                    header(snapshot, today: today)
                        .frame(height: OverviewRoom.head)
                    if room.top > 0 {
                        Hairline()
                        topRow(snapshot, height: room.top)
                            .frame(height: room.top)
                    }
                    if room.week > 0 {
                        Hairline()
                        weekStrip(snapshot, today: today, height: room.week)
                    }
                    if room.lists > 0 {
                        Hairline()
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(lists.enumerated()), id: \.offset) { index, kind in
                                if index > 0 { Rectangle().fill(Palette.line).frame(width: 1) }
                                ListColumn(snapshot: snapshot, kind: kind, today: today, height: room.lists)
                            }
                        }
                        .frame(height: room.lists)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .widgetURL(WidgetLink.calendar(DayKey.of(entry.date)))
    }

    /// The day, and how long has been studied today (against the goal, when
    /// there is one).
    private func header(_ snapshot: Snapshot, today: String) -> some View {
        let lang = snapshot.lang
        let hours = snapshot.studied(on: today)
        let goal = snapshot.goal
        return HStack(alignment: .center, spacing: 8) {
            Text(Clock.format(entry.date, template: "EEEEdMMM", lang: lang))
                .font(Typo.heading(16))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            if parts.study {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(L10n.t("studied", lang))
                            .font(Typo.text(10, .semibold))
                            .foregroundStyle(Palette.inkSoft)
                        Text(Clock.duration(hours: hours, lang: lang))
                            .font(Typo.number(12.5, .bold))
                            .foregroundStyle(Palette.ink)
                    }
                    .lineLimit(1)
                    if goal > 0 {
                        ProgressCapsule(fraction: min(1, hours / goal))
                            .frame(width: 96, height: 5)
                    }
                }
            }
        }
    }

    /// This month beside what is coming up, or whichever of the two is on.
    @ViewBuilder private func topRow(_ snapshot: Snapshot, height: CGFloat) -> some View {
        let today = DayKey.of(entry.date)
        // A heading of about 22 points, then a row every 19.
        let limit = max(1, Int((height - 22) / 19))
        HStack(alignment: .top, spacing: 12) {
            if parts.month {
                Link(destination: WidgetLink.calendar(today)) {
                    MiniMonth(snapshot: snapshot, now: entry.date)
                }
                .frame(maxWidth: parts.upNext ? 136 : .infinity)
            }
            if parts.month && parts.upNext {
                Rectangle().fill(Palette.line).frame(width: 1)
            }
            if parts.upNext {
                Link(destination: WidgetLink.todos()) {
                    UpNextList(snapshot: snapshot, now: entry.date, limit: limit)
                }
            }
        }
    }

    /// This week's seven days, as the Week widget draws them.
    private func weekStrip(_ snapshot: Snapshot, today: String, height: CGFloat) -> some View {
        let start = Clock.weekStart(of: today, first: snapshot.weekStart)
        let names = Clock.weekdays(lang: snapshot.lang, first: snapshot.weekStart)
        // Weekday and number take about 38 points; a chip and its gap 16.
        let chips = max(1, Int((height - 38) / 16))
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                let day = DayKey.add(start, days: index)
                Link(destination: WidgetLink.calendar(day)) {
                    DayCell(snapshot: snapshot, day: day, today: today, weekday: names[index], chips: chips)
                }
            }
        }
        .frame(height: height)
    }
}

/// How the Overview's height is shared out among the parts that are on.
/// Every part after the header costs 17 points besides its own height: a
/// hairline and the space on each side of it.
struct OverviewRoom {
    static let head: CGFloat = 26
    var top: CGFloat = 0
    var week: CGFloat = 0
    var lists: CGFloat = 0

    init(parts: OverviewParts, height: CGFloat) {
        let hasTop = parts.month || parts.upNext
        let hasWeek = parts.week
        let hasLists = !parts.lists.isEmpty
        let count = [hasTop, hasWeek, hasLists].filter { $0 }.count
        var rest = max(0, height - Self.head - CGFloat(count) * 17)
        if hasTop {
            top = hasWeek || hasLists ? min(132, rest) : rest
            rest = max(0, rest - top)
        }
        if hasWeek && hasLists {
            week = max(96, (rest * 0.45).rounded())
            lists = max(60, rest - week)
        } else if hasWeek {
            week = rest
        } else if hasLists {
            lists = rest
        }
    }
}

/// A line between the parts.
private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// One to-do list in a column: its name and count, and as many rows as fit.
struct ListColumn: View {
    let snapshot: Snapshot
    let kind: ListKind
    let today: String
    let height: CGFloat

    var body: some View {
        let rows = snapshot.list(kind, today: today)
        let open = rows.filter { !$0.done }.count
        let rowHeight: CGFloat = 19
        let fit = max(1, Int((height - 26) / rowHeight))
        let shown = rows.count > fit ? Array(rows.prefix(fit - 1)) : rows
        Link(destination: WidgetLink.todos()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    Text(L10n.t(kind.titleKey, snapshot.lang))
                        .font(Typo.heading(13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if open > 0 { CountPill(count: open) }
                }
                .frame(height: 20)
                .padding(.bottom, 4)
                if rows.isEmpty {
                    EmptyNote(text: L10n.t("listEmpty", snapshot.lang))
                } else {
                    ForEach(shown) { row in
                        HStack(spacing: 6) {
                            TodoBox(done: row.done, size: 12)
                            Text(row.title)
                                .font(Typo.text(12, .medium))
                                .foregroundStyle(row.done ? Palette.inkSoft : Palette.ink)
                                .strikethrough(row.done, color: Palette.inkSoft)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let when = row.when {
                                Text(when)
                                    .font(Typo.number(10))
                                    .foregroundStyle(Palette.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        .frame(height: rowHeight)
                    }
                    if rows.count > shown.count {
                        MoreLine(count: rows.count - shown.count, lang: snapshot.lang, size: 10.5)
                            .padding(.leading, 18)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
