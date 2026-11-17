import AppIntents
import SwiftUI
import WidgetKit

@main
struct TrackerWidgets: WidgetBundle {
    var body: some Widget {
        DayWidget()
        UpNextWidget()
        WeekWidget()
        MonthWidget()
        TodoListWidget()
        StudyWidget()
        YearWidget()
        if #available(iOS 27.0, *) {
            OverviewWidget()
        }
    }
}

/// The page's language for the gallery's names (what the app last stored).
private func name(_ key: String) -> String {
    L10n.t(key, SharedStore.load()?.lang ?? L10n.lang(nil))
}

/// Every widget on the site's card; the small Lock Screen ones on nothing
/// (iOS draws their ground).
struct Card<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch family {
        case .accessoryCircular:
            content().containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular, .accessoryInline:
            content().containerBackground(for: .widget) { Color.clear }
        default:
            content()
                .padding(13)
                .containerBackground(for: .widget) { Palette.paperDim }
        }
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Day", provider: DayProvider()) { entry in
            Card { DayView(entry: entry) }
        }
        .configurationDisplayName(name("wDayName"))
        .description(name("wDayDesc"))
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNext", provider: DayProvider()) { entry in
            Card { UpNextView(entry: entry) }
        }
        .configurationDisplayName(name("wUpNextName"))
        .description(name("wUpNextDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Week", provider: DayProvider()) { entry in
            Card { WeekView(entry: entry) }
        }
        .configurationDisplayName(name("wWeekName"))
        .description(name("wWeekDesc"))
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FiveWeeks", provider: DayProvider()) { entry in
            Card { MonthView(entry: entry) }
        }
        .configurationDisplayName(name("wMonthName"))
        .description(name("wMonthDesc"))
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Study", provider: DayProvider()) { entry in
            Card { StudyView(entry: entry) }
        }
        .configurationDisplayName(name("wStudyName"))
        .description(name("wStudyDesc"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct YearWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Year", provider: DayProvider()) { entry in
            Card { YearView(entry: entry) }
        }
        .configurationDisplayName(name("wYearName"))
        .description(name("wYearDesc"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// A whole home screen page (iOS 27's extra-large iPhone size): the month,
/// what is next, the week and the to-do lists together.
@available(iOS 27.0, *)
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Overview", provider: DayProvider()) { entry in
            Card { OverviewView(entry: entry) }
        }
        .configurationDisplayName(name("wOverviewName"))
        .description(name("wOverviewDesc"))
        .supportedFamilies([.systemExtraLargePortrait])
        .contentMarginsDisabled()
    }
}

// MARK: - The list widget, with its list chosen in the widget's settings

enum TodoListChoice: String, AppEnum {
    case today, week, month, year, upcoming

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [TodoListChoice: DisplayRepresentation] = [
        .today: "Today",
        .week: "This week",
        .month: "This month",
        .year: "This year",
        .upcoming: "Upcoming",
    ]

    var kind: ListKind { ListKind(rawValue: rawValue) ?? .today }
}

struct TodoListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "To-do list"
    static let description = IntentDescription("Choose which to-dos the widget shows.")

    @Parameter(title: "List", default: .today)
    var list: TodoListChoice

    init() {}
}

struct ListEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let list: ListKind
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: Date(), snapshot: .sample, list: .today)
    }

    func snapshot(for configuration: TodoListIntent, in context: Context) async -> ListEntry {
        let stored = SharedStore.load()
        return ListEntry(date: Date(), snapshot: context.isPreview && stored == nil ? .sample : stored, list: configuration.list.kind)
    }

    func timeline(for configuration: TodoListIntent, in context: Context) async -> Timeline<ListEntry> {
        let snapshot = SharedStore.load()
        let dates = DayProvider.moments(from: Date(), snapshot: nil)
        return Timeline(entries: dates.map { ListEntry(date: $0, snapshot: snapshot, list: configuration.list.kind) }, policy: .atEnd)
    }
}

struct TodoListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodoList", intent: TodoListIntent.self, provider: ListProvider()) { entry in
            Card { TodoListView(entry: entry) }
        }
        .configurationDisplayName(name("wTodoName"))
        .description(name("wTodoDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
