import SwiftUI
import WidgetKit

// MARK: - A to-do list

struct TodoListView: View {
    let entry: ListEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let today = DayKey.of(entry.date)
            let rows = snapshot.list(entry.list, today: today)
            GeometryReader { geo in
                let rowHeight: CGFloat = 20
                let fit = max(1, Int((geo.size.height - 30) / rowHeight))
                let shown = rows.count > fit ? Array(rows.prefix(fit - 1)) : rows
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(L10n.t(entry.list.titleKey, snapshot.lang))
                            .font(Typo.heading(14))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !rows.isEmpty { CountPill(count: rows.count) }
                    }
                    .frame(height: 22)
                    .padding(.bottom, 4)
                    if rows.isEmpty {
                        EmptyNote(text: L10n.t(entry.list == .today ? "allDone" : "listEmpty", snapshot.lang))
                    } else {
                        ForEach(shown) { row in
                            HStack(spacing: 7) {
                                TodoBox(done: false, size: 13)
                                Text(row.title)
                                    .font(Typo.text(13, .medium))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if let when = row.when, family != .systemSmall || row.title.count < 12 {
                                    Text(when)
                                        .font(Typo.number(10.5))
                                        .foregroundStyle(Palette.inkSoft)
                                        .lineLimit(1)
                                }
                            }
                            .frame(height: rowHeight)
                        }
                        if rows.count > shown.count {
                            MoreLine(count: rows.count - shown.count, lang: snapshot.lang)
                                .padding(.leading, 20)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .widgetURL(WidgetLink.todos())
    }
}

// MARK: - Year

/// How much of the year has gone: twelve months, the past ones filled with
/// the "on" green, this one as far as today.
struct YearView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let lang = entry.snapshot?.lang ?? L10n.lang(nil)
        let calendar = Calendar.current
        let now = entry.date
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? now
        let total = max(1, calendar.dateComponents([.day], from: startOfYear, to: nextYear).day ?? 365)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let percent = Int((Double(dayOfYear - 1) * 100 / Double(total)).rounded(.down))
        // Today counts as still to come.
        let left = total - dayOfYear + 1
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(year))
                    .font(Typo.heading(family == .systemSmall ? 17 : 19))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Text("\(percent)%")
                    .font(Typo.number(family == .systemSmall ? 17 : 19, .bold))
                    .foregroundStyle(Palette.ink)
            }
            if family == .systemSmall {
                Spacer(minLength: 0)
                ProgressCapsule(fraction: Double(percent) / 100)
                    .frame(height: 7)
                Spacer(minLength: 0)
                Text(L10n.t("yearGone", lang).replacingOccurrences(of: "{p}", with: String(percent)))
                    .font(Typo.text(11, .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                Text(L10n.count("daysLeft", left, lang))
                    .font(Typo.text(11, .semibold))
                    .foregroundStyle(Palette.ink)
            } else {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(1...12, id: \.self) { m in
                        VStack(spacing: 3) {
                            MonthPill(fraction: fraction(month: m, now: now, current: month), current: m == month)
                            Text(String(m))
                                .font(Typo.number(9, m == month ? .bold : .medium))
                                .foregroundStyle(m == month ? Palette.ink : Palette.inkSoft)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Text(L10n.t("yearGone", lang).replacingOccurrences(of: "{p}", with: String(percent)))
                    Spacer(minLength: 6)
                    Text(L10n.count("daysLeft", left, lang))
                }
                .font(Typo.text(11, .medium))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
            }
        }
        .widgetURL(WidgetLink.calendar(DayKey.of(now)))
    }

    private func fraction(month m: Int, now: Date, current: Int) -> Double {
        if m < current { return 1 }
        if m > current { return 0 }
        let calendar = Calendar.current
        let day = calendar.component(.day, from: now)
        let length = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        return Double(day - 1) / Double(length)
    }
}

struct MonthPill: View {
    let fraction: Double
    let current: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Palette.paper
                Palette.on
                    .frame(height: geo.size.height * fraction)
                    .widgetAccentable()
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(current ? Palette.celadon : Palette.line, lineWidth: current ? 1.5 : 1))
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProgressCapsule: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.paper)
                Capsule().fill(Palette.on)
                    .frame(width: max(geo.size.height, geo.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
                    .widgetAccentable()
            }
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
        }
    }
}

// MARK: - Today's study and to-dos

struct StudyView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Gate(snapshot: entry.snapshot) { snapshot in
            let lang = snapshot.lang
            let today = DayKey.of(entry.date)
            let hours = snapshot.studied(on: today)
            let goal = snapshot.goal
            let fraction = goal > 0 ? min(1, hours / goal) : 0
            let open = snapshot.list(.today, today: today).count
            let left = open == 0 ? L10n.t("allDone", lang) : L10n.count("todosLeft", open, lang)
            switch family {
            case .accessoryCircular:
                Gauge(value: fraction) {
                    Text("")
                } currentValueLabel: {
                    Text(clock(hours))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("studied", lang))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Clock.duration(hours: hours, lang: lang))
                        .font(.headline)
                        .widgetAccentable()
                    Gauge(value: fraction) { Text("") }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            case .accessoryInline:
                Text("\(Clock.duration(hours: hours, lang: lang)) \u{00B7} \(left)")
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("studied", lang))
                        .font(Typo.text(11, .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                    Text(Clock.duration(hours: hours, lang: lang))
                        .font(Typo.number(26, .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ProgressCapsule(fraction: fraction)
                        .frame(height: 7)
                    if goal > 0 {
                        Text(L10n.t("goalOf", lang).replacingOccurrences(of: "{g}", with: Clock.duration(hours: goal, lang: lang)))
                            .font(Typo.text(10.5, .medium))
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        TodoBox(done: open == 0, size: 12)
                        Text(left)
                            .font(Typo.text(11.5, .semibold))
                            .foregroundStyle(open == 0 ? Palette.on : Palette.ink)
                            .lineLimit(1)
                    }
                }
            }
        }
        .widgetURL(WidgetLink.todos())
    }

    /// 1:25, for the round one.
    private func clock(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
