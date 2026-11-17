import SwiftUI
import WidgetKit

/// The whole-page widget (iOS 27's extra-large iPhone size, 4 x 6): today
/// and today's studying, this month beside what is coming up (the Up next
/// widget's medium face), the week day by day (the Week widget's cells), and
/// this week's and this month's to-dos side by side. Each part opens its own
/// place on the site.
struct OverviewView: View {
    let entry: DayEntry

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            GeometryReader { geo in
                // Seven parts with 8 points between them; three are hairlines.
                let head: CGFloat = 26
                let top: CGFloat = 132
                let rest = max(0, geo.size.height - head - top - 6 * 8 - 3)
                let week = max(96, (rest * 0.45).rounded())
                let lists = max(60, rest - week)
                VStack(alignment: .leading, spacing: 8) {
                    header(snapshot, today: today)
                        .frame(height: head)
                    Hairline()
                    HStack(alignment: .top, spacing: 12) {
                        Link(destination: WidgetLink.calendar(today)) {
                            MiniMonth(snapshot: snapshot, now: entry.date)
                        }
                        .frame(width: 136)
                        Rectangle().fill(Palette.line).frame(width: 1)
                        Link(destination: WidgetLink.todos()) {
                            UpNextList(snapshot: snapshot, now: entry.date, limit: 5)
                        }
                    }
                    .frame(height: top)
                    Hairline()
                    weekStrip(snapshot, today: today, height: week)
                    Hairline()
                    HStack(alignment: .top, spacing: 12) {
                        ListColumn(snapshot: snapshot, kind: .week, today: today, height: lists)
                        Rectangle().fill(Palette.line).frame(width: 1)
                        ListColumn(snapshot: snapshot, kind: .month, today: today, height: lists)
                    }
                    .frame(height: lists)
                }
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

    /// This week's seven days, as the Week widget draws them.
    private func weekStrip(_ snapshot: Snapshot, today: String, height: CGFloat) -> some View {
        let start = Clock.weekStart(of: today, first: snapshot.weekStart)
        let names = Clock.weekdays(lang: snapshot.lang, first: snapshot.weekStart)
        // Weekday and number take about 34 points; a chip 14.
        let chips = max(1, Int((height - 38) / 14))
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

/// A line between the parts.
private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// One to-do list in a column: its name and count, and as many rows as fit.
private struct ListColumn: View {
    let snapshot: Snapshot
    let kind: ListKind
    let today: String
    let height: CGFloat

    var body: some View {
        let rows = snapshot.list(kind, today: today)
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
                    if !rows.isEmpty { CountPill(count: rows.count) }
                }
                .frame(height: 20)
                .padding(.bottom, 4)
                if rows.isEmpty {
                    EmptyNote(text: L10n.t("listEmpty", snapshot.lang))
                } else {
                    ForEach(shown) { row in
                        HStack(spacing: 6) {
                            TodoBox(done: false, size: 12)
                            Text(row.title)
                                .font(Typo.text(12, .medium))
                                .foregroundStyle(Palette.ink)
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
