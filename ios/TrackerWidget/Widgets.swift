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
        AppIntentConfiguration(kind: "Day", intent: DayIntent.self, provider: ConfiguredProvider<DayIntent>()) { entry in
            Card { DayView(entry: entry.day, todos: entry.config.todos, done: entry.config.done) }
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
        AppIntentConfiguration(kind: "Week", intent: CalendarIntent.self, provider: ConfiguredProvider<CalendarIntent>()) { entry in
            Card { WeekView(entry: entry.day, todos: entry.config.todos) }
        }
        .configurationDisplayName(name("wWeekName"))
        .description(name("wWeekDesc"))
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FiveWeeks", intent: CalendarIntent.self, provider: ConfiguredProvider<CalendarIntent>()) { entry in
            Card { MonthView(entry: entry.day, todos: entry.config.todos) }
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
        AppIntentConfiguration(kind: "Overview", intent: OverviewIntent.self, provider: ConfiguredProvider<OverviewIntent>()) { entry in
            Card { OverviewView(entry: entry.day, parts: entry.config.parts) }
        }
        .configurationDisplayName(name("wOverviewName"))
        .description(name("wOverviewDesc"))
        .supportedFamilies([.systemExtraLargePortrait])
        .contentMarginsDisabled()
    }
}

// MARK: - The list widget, with its list chosen in the widget's settings

enum TodoListChoice: String, AppEnum {
    case today, tomorrow, week, month, year, upcoming

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [TodoListChoice: DisplayRepresentation] = [
        .today: "Today",
        .tomorrow: "Tomorrow",
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

// MARK: - What the other widgets show, chosen in their settings

/// The entry of a widget with settings: the day, the page's data and what
/// the widget was set to show.
struct ConfiguredEntry<Intent: WidgetConfigurationIntent>: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let config: Intent

    var day: DayEntry { DayEntry(date: date, snapshot: snapshot) }
}

/// The same timeline as `DayProvider` (now, each midnight, each timed thing
/// of today), carrying the widget's settings.
struct ConfiguredProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConfiguredEntry<Intent> {
        ConfiguredEntry(date: Date(), snapshot: .sample, config: Intent())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ConfiguredEntry<Intent> {
        let stored = SharedStore.load()
        return ConfiguredEntry(date: Date(), snapshot: context.isPreview && stored == nil ? .sample : stored, config: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<ConfiguredEntry<Intent>> {
        let snapshot = SharedStore.load()
        let dates = DayProvider.moments(from: Date(), snapshot: snapshot)
        return Timeline(entries: dates.map { ConfiguredEntry(date: $0, snapshot: snapshot, config: configuration) }, policy: .atEnd)
    }
}

/// The Day widget: the day's events, and its to-dos (the finished ones
/// crossed out) unless left out.
struct DayIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Day"
    static let description = IntentDescription("Choose what the day shows.")

    @Parameter(title: "To-dos", default: true)
    var todos: Bool

    @Parameter(title: "Finished to-dos", default: true)
    var done: Bool

    /// "Finished to-dos" means nothing with the to-dos left out.
    static var parameterSummary: some ParameterSummary {
        When(\.$todos, .equalTo, true) {
            Summary {
                \.$todos
                \.$done
            }
        } otherwise: {
            Summary {
                \.$todos
            }
        }
    }

    init() {}
}

/// The Week and Five weeks widgets: each day's to-dos as one chip (done of
/// all), or events only.
struct CalendarIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Calendar"
    static let description = IntentDescription("Choose what the days show.")

    @Parameter(title: "To-dos", default: true)
    var todos: Bool

    init() {}
}

/// A list in the Overview, or none.
enum OverviewListChoice: String, AppEnum {
    case none, today, tomorrow, week, month, year, upcoming

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [OverviewListChoice: DisplayRepresentation] = [
        .none: "None",
        .today: "Today",
        .tomorrow: "Tomorrow",
        .week: "This week",
        .month: "This month",
        .year: "This year",
        .upcoming: "Upcoming",
    ]

    var kind: ListKind? { ListKind(rawValue: rawValue) }
}

/// The Overview: which parts it shows and which two to-do lists.
struct OverviewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Overview"
    static let description = IntentDescription("Choose what the page shows.")

    @Parameter(title: "Study time", default: true)
    var study: Bool

    @Parameter(title: "Month", default: true)
    var month: Bool

    @Parameter(title: "Up next", default: true)
    var upNext: Bool

    @Parameter(title: "Week", default: true)
    var week: Bool

    @Parameter(title: "First list", default: .week)
    var first: OverviewListChoice

    @Parameter(title: "Second list", default: .month)
    var second: OverviewListChoice

    init() {}

    var parts: OverviewParts {
        var lists: [ListKind] = []
        for kind in [first.kind, second.kind].compactMap({ $0 }) where !lists.contains(kind) {
            lists.append(kind)
        }
        return OverviewParts(study: study, month: month, upNext: upNext, week: week, lists: lists)
    }
}
