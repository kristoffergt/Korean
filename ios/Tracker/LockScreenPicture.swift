import AppIntents
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

// The lock screen takes only small widgets, so a bigger calendar goes there
// as the wallpaper itself: a Shortcuts action draws the calendar and to-dos
// over a photo at the phone's own size, and Set Wallpaper Photo puts it on
// the lock screen. A personal automation (Time of Day) keeps it fresh, and
// can show another layout at each time, or take turns between several.

/// How the picture is laid out.
enum LockLayout: String, AppEnum {
    case monthLists, weekDay, yearWeeks, dayLists, rotate

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
    static let caseDisplayRepresentations: [LockLayout: DisplayRepresentation] = [
        .monthLists: "Month and to-do lists",
        .weekDay: "Week and today",
        .yearWeeks: "Year and five weeks",
        .dayLists: "Today and to-do lists",
        .rotate: "A different one each time",
    ]

    static let drawn: [LockLayout] = [.monthLists, .weekDay, .yearWeeks, .dayLists]
}

/// The panels' colours.
enum LockPanels: String, AppEnum {
    case phone, dark, light

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Panels"
    static let caseDisplayRepresentations: [LockPanels: DisplayRepresentation] = [
        .phone: "Match the phone",
        .dark: "Dark",
        .light: "Light",
    ]
}

/// A to-do list on the picture, or none.
enum LockList: String, AppEnum {
    case none, today, tomorrow, week, month, year, upcoming

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let caseDisplayRepresentations: [LockList: DisplayRepresentation] = [
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

struct MakeLockScreenPicture: AppIntent {
    static let title: LocalizedStringResource = "Make Lock Screen Picture"
    static let description = IntentDescription(
        "Draws your calendar and to-dos as a picture the size of this phone's screen. Hand it to Set Wallpaper Photo to put it on the lock screen."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Layout", default: .monthLists)
    var layout: LockLayout

    @Parameter(title: "Layouts to take turns")
    var rotation: [LockLayout]?

    @Parameter(title: "Photo", supportedContentTypes: [.image])
    var photo: IntentFile?

    @Parameter(title: "Panels", default: .phone)
    var panels: LockPanels

    @Parameter(title: "Room for lock screen widgets", default: true)
    var widgetRow: Bool

    @Parameter(title: "First list", default: .today)
    var firstList: LockList

    @Parameter(title: "Second list", default: .week)
    var secondList: LockList

    // What cannot change the picture is not shown: the turns only for "A
    // different one each time", the lists only for a layout that has them.
    static var parameterSummary: some ParameterSummary {
        Switch(\.$layout) {
            Case(.weekDay) {
                Summary("Make a lock screen picture of \(\.$layout)") {
                    \.$photo
                    \.$panels
                    \.$widgetRow
                }
            }
            Case(.yearWeeks) {
                Summary("Make a lock screen picture of \(\.$layout)") {
                    \.$photo
                    \.$panels
                    \.$widgetRow
                }
            }
            Case(.rotate) {
                Summary("Make a lock screen picture of \(\.$layout)") {
                    \.$rotation
                    \.$photo
                    \.$panels
                    \.$widgetRow
                    \.$firstList
                    \.$secondList
                }
            }
            DefaultCase {
                Summary("Make a lock screen picture of \(\.$layout)") {
                    \.$photo
                    \.$panels
                    \.$widgetRow
                    \.$firstList
                    \.$secondList
                }
            }
        }
    }

    init() {}

    /// On the main thread: SwiftUI draws the picture there.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let drawn = layout == .rotate ? LockTurns.next(from: rotation) : layout
        let scheme: ColorScheme
        switch panels {
        case .dark: scheme = .dark
        case .light: scheme = .light
        case .phone: scheme = UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        let lists = [firstList.kind, secondList.kind].compactMap { $0 }
        guard let png = LockPicture.png(layout: drawn, snapshot: SharedStore.load(), photo: photo?.data,
                                        scheme: scheme, widgetRow: widgetRow, lists: lists) else {
            throw LockPictureError.notDrawn
        }
        return .result(value: IntentFile(data: png, filename: "lock-screen.png", type: .png))
    }
}

enum LockPictureError: Error, CustomLocalizedStringResourceConvertible {
    case notDrawn

    var localizedStringResource: LocalizedStringResource {
        "The picture could not be drawn."
    }
}

/// "A different one each time": the layouts in turn, remembered between
/// runs, so each run of the automation shows the next.
enum LockTurns {
    private static let key = "lockPicture.nextTurn"

    static func next(from chosen: [LockLayout]?) -> LockLayout {
        var turns = (chosen ?? []).filter { $0 != .rotate }
        if turns.isEmpty { turns = LockLayout.drawn }
        let index = UserDefaults.standard.integer(forKey: key) % turns.count
        UserDefaults.standard.set(index + 1, forKey: key)
        return turns[index]
    }
}

// MARK: - The picture

/// The whole screen: the photo (or the site's own soft green), and the
/// panels in the part of the lock screen nothing else covers, between the
/// clock (and the widget row under it, when room is left for it) and the
/// torch and camera buttons.
struct LockPicture: View {
    let layout: LockLayout
    let snapshot: Snapshot?
    let now: Date
    let photo: UIImage?
    let widgetRow: Bool
    let lists: [ListKind]

    var body: some View {
        GeometryReader { geo in
            let top = (geo.size.height * (widgetRow ? 0.405 : 0.31)).rounded()
            let bottom = (geo.size.height * 0.845).rounded()
            ZStack(alignment: .topLeading) {
                ground(geo.size)
                VStack(spacing: 10) {
                    panels(height: bottom - top)
                }
                .padding(.horizontal, 16)
                .frame(width: geo.size.width, height: bottom - top)
                .offset(y: top)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder private func ground(_ size: CGSize) -> some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            LinearGradient(colors: [Palette.onSoft, Palette.paper], startPoint: .top, endPoint: .bottom)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder private func panels(height: CGFloat) -> some View {
        let entry = DayEntry(date: now, snapshot: snapshot)
        let today = DayKey.of(now)
        let room = height - 10
        switch layout {
        case .weekDay:
            let first = min(150, (room * 0.38).rounded())
            Panel(height: first) {
                Gate(snapshot: snapshot) { snapshot in
                    WeekStrip(snapshot: snapshot, today: today, height: first - 26)
                }
            }
            Panel(height: room - first) {
                DayView(entry: entry, size: .systemLarge)
            }
        case .yearWeeks:
            let first = min(112, (room * 0.3).rounded())
            Panel(height: first) {
                YearView(entry: entry, size: .systemMedium)
            }
            Panel(height: room - first) {
                MonthView(entry: entry)
            }
        case .dayLists:
            if lists.isEmpty {
                Panel(height: height) {
                    DayView(entry: entry, size: .systemLarge)
                }
            } else {
                let first = (room * 0.5).rounded()
                Panel(height: first) {
                    DayView(entry: entry, size: .systemLarge)
                }
                Panel(height: room - first) {
                    ListPair(snapshot: snapshot, lists: lists, today: today, height: room - first - 26)
                }
            }
        case .monthLists, .rotate:
            if lists.isEmpty {
                Panel(height: height) {
                    MonthAndNext(snapshot: snapshot, now: now, height: height - 26)
                }
            } else {
                let first = min(172, (room * 0.46).rounded())
                Panel(height: first) {
                    MonthAndNext(snapshot: snapshot, now: now, height: first - 26)
                }
                Panel(height: room - first) {
                    ListPair(snapshot: snapshot, lists: lists, today: today, height: room - first - 26)
                }
            }
        }
    }

    /// The picture as a PNG at this phone's screen size and scale.
    @MainActor
    static func png(layout: LockLayout, snapshot: Snapshot?, photo: Data?, scheme: ColorScheme,
                    widgetRow: Bool, lists: [ListKind], now: Date = Date()) -> Data? {
        let screen = UIScreen.main
        let size = CGSize(width: min(screen.bounds.width, screen.bounds.height),
                          height: max(screen.bounds.width, screen.bounds.height))
        let scale = screen.scale
        let background = photo.flatMap { image(from: $0, longest: max(size.width, size.height) * scale) }
        let picture = LockPicture(
            layout: layout,
            snapshot: snapshot,
            now: now,
            photo: background,
            widgetRow: widgetRow,
            lists: lists.reduce(into: [ListKind]()) { if !$0.contains($1) { $0.append($1) } }
        )
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: picture)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        // The first picture a newly started app draws can come back empty
        // (seen on the simulator: the first of the samples was missing), and
        // a Shortcuts run is exactly that first picture. Each read of
        // `uiImage` draws again.
        for _ in 0..<3 {
            if let png = renderer.uiImage?.pngData() { return png }
        }
        return nil
    }

    #if DEBUG
    /// `-TRDrawLockPictures YES` at launch writes every layout, dark and
    /// light, drawn from the widgets' sample day, into the app's
    /// Documents/LockPictures, for looking at them without Shortcuts.
    @MainActor
    static func drawSamples() {
        guard UserDefaults.standard.bool(forKey: "TRDrawLockPictures"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let folder = documents.appendingPathComponent("LockPictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for layout in LockLayout.drawn {
            for (name, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
                if let png = png(layout: layout, snapshot: .sample, photo: nil, scheme: scheme,
                                 widgetRow: true, lists: [.today, .week]) {
                    try? png.write(to: folder.appendingPathComponent("\(layout.rawValue)-\(name).png"))
                }
            }
        }
    }
    #endif

    /// Reads a photo at no more pixels than the screen has (a phone photo
    /// read whole can be bigger than the memory allowed for this).
    static func image(from data: Data, longest: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(longest),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A panel: the widgets' card, a little see-through over the photo.
private struct Panel<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(13)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.paperDim.opacity(0.9))
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// This month beside what is coming up (the Up next widget's medium face).
private struct MonthAndNext: View {
    let snapshot: Snapshot?
    let now: Date
    let height: CGFloat

    var body: some View {
        Gate(snapshot: snapshot) { snapshot in
            HStack(alignment: .top, spacing: 12) {
                MiniMonth(snapshot: snapshot, now: now)
                    .frame(width: 150)
                Rectangle().fill(Palette.line).frame(width: 1)
                UpNextList(snapshot: snapshot, now: now, limit: max(1, Int((height - 22) / 19)))
            }
        }
    }
}

/// The week's seven days, as the Week widget draws them.
private struct WeekStrip: View {
    let snapshot: Snapshot
    let today: String
    let height: CGFloat

    var body: some View {
        let start = Clock.weekStart(of: today, first: snapshot.weekStart)
        let names = Clock.weekdays(lang: snapshot.lang, first: snapshot.weekStart)
        let chips = max(1, Int((height - 38) / 16))
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                DayCell(snapshot: snapshot, day: DayKey.add(start, days: index), today: today,
                        weekday: names[index], chips: chips)
            }
        }
        .frame(height: height)
    }
}

/// One or two to-do lists side by side.
private struct ListPair: View {
    let snapshot: Snapshot?
    let lists: [ListKind]
    let today: String
    let height: CGFloat

    var body: some View {
        Gate(snapshot: snapshot) { snapshot in
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(lists.prefix(2).enumerated()), id: \.offset) { index, kind in
                    if index > 0 { Rectangle().fill(Palette.line).frame(width: 1) }
                    ListColumn(snapshot: snapshot, kind: kind, today: today, height: height)
                }
            }
            .frame(height: height, alignment: .top)
        }
    }
}
