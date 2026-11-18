import CoreText
import SwiftUI
import WidgetKit

/// The site's colour tokens (index.html :root and body.dark), light and dark.
enum Palette {
    static let paper = dynamic(0xF5F5F6, 0x18191B)
    static let paperDim = dynamic(0xEAEAEC, 0x232427)
    static let ink = dynamic(0x1E1F22, 0xEDEDEF)
    static let inkSoft = dynamic(0x6B6D72, 0x9A9CA1)
    static let line = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 237 / 255, green: 237 / 255, blue: 239 / 255, alpha: 0.14)
            : UIColor(red: 30 / 255, green: 31 / 255, blue: 34 / 255, alpha: 0.12)
    })
    /// --celadon-4: the today ring and the "Today" tag, the same in both themes.
    static let celadon = Color(hex: 0x4F7563)
    /// --on: something that IS on (a done to-do, time studied).
    static let on = dynamic(0x4F7563, 0x86B49F)
    static let onSoft = dynamic(0xDCE7DA, 0x2E3A34)
    /// The events' default colour (an event with none of its own).
    static let eventDefault = "#4F7563"

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// An event's chip colour and the ink that reads on it (the site's
/// textColorFor: dark ink on a light colour, white on the rest).
struct ChipColors {
    let fill: Color
    let text: Color

    init(_ css: String?) {
        let parsed = CSSColor.parse(css) ?? CSSColor.parse(Palette.eventDefault)!
        fill = Color(.sRGB, red: parsed.0, green: parsed.1, blue: parsed.2, opacity: 1)
        let luminance = 0.299 * parsed.0 + 0.587 * parsed.1 + 0.114 * parsed.2
        text = luminance > 0.6 ? Color(hex: 0x1E1F22) : .white
    }
}

/// The site's three faces: Inter for text, Noto Serif KR for headings and
/// Space Grotesk for numbers. When their files are in the widget's Fonts
/// folder they are used; otherwise the closest of the phone's own.
enum Typo {
    private static let registered: Bool = {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    private static func has(_ name: String) -> Bool {
        _ = registered
        return UIFont(name: name, size: 12) != nil
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if has("Inter") { return .custom("Inter", size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    static func heading(_ size: CGFloat) -> Font {
        if has("NotoSerifKR-Bold") { return .custom("NotoSerifKR-Bold", size: size) }
        return .system(size: size, weight: .bold, design: .serif)
    }

    static func number(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        if has("SpaceGrotesk-Regular") { return .custom("SpaceGrotesk-Regular", size: size).weight(weight) }
        return .system(size: size, weight: weight).monospacedDigit()
    }
}

// MARK: - The site's small parts

/// A to-do's box (.todo-check): a rounded square, filled green when done.
struct TodoBox: View {
    let done: Bool
    var size: CGFloat = 13

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .strokeBorder(done ? Palette.on : Palette.inkSoft, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(done ? Palette.on : Color.clear)
            )
            .overlay {
                if done {
                    Path { path in
                        path.move(to: CGPoint(x: size * 0.26, y: size * 0.52))
                        path.addLine(to: CGPoint(x: size * 0.43, y: size * 0.69))
                        path.addLine(to: CGPoint(x: size * 0.75, y: size * 0.33))
                    }
                    .stroke(Palette.paper, style: StrokeStyle(lineWidth: max(1.4, size * 0.13), lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size, height: size)
            .widgetAccentable(done)
    }
}

/// A calendar event as the month grid draws it (.cal-chip): its own colour,
/// square on a side where it carries on from or into another day.
struct EventChip: View {
    let title: String
    let color: String?
    var continuesIn = false
    var continuesOut = false
    var size: CGFloat = 10
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let colors = ChipColors(color)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: continuesIn ? 0 : 3.5,
            bottomLeadingRadius: continuesIn ? 0 : 3.5,
            bottomTrailingRadius: continuesOut ? 0 : 3.5,
            topTrailingRadius: continuesOut ? 0 : 3.5,
            style: .continuous
        )
        Text(continuesIn ? " " : title)
            .font(Typo.text(size, .medium))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(mode == .fullColor ? colors.text : Palette.ink)
            .background {
                if mode == .fullColor {
                    shape.fill(colors.fill)
                } else {
                    shape.fill(Palette.ink.opacity(0.18))
                }
            }
    }
}

/// A day's to-dos on the calendar, all in one chip: the box (filled once
/// every one of them is done) and how many are done of how many. A finished
/// day goes quiet, so a day with something left stands out in the week and
/// the five weeks.
struct TodoBunchChip: View {
    let done: Int
    let total: Int
    var size: CGFloat = 10

    var body: some View {
        let all = done >= total
        HStack(spacing: 3) {
            TodoBox(done: all, size: size * 0.9)
            Text("\(done)/\(total)")
                .font(Typo.number(size, .semibold))
                .foregroundStyle(all ? Palette.inkSoft : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if all {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(Palette.onSoft)
            }
        }
        .overlay {
            if !all {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Palette.inkSoft.opacity(0.8), style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.6]))
            }
        }
    }
}

/// The "Today" tag (.cal-today-tag).
struct TodayTag: View {
    let lang: String

    var body: some View {
        Text(L10n.t("today", lang))
            .font(Typo.text(9, .bold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .foregroundStyle(.white)
            .background(Capsule().fill(Palette.celadon))
            .widgetAccentable()
    }
}

/// A count in a capsule beside a heading.
struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(Typo.number(11.5, .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .foregroundStyle(Palette.ink)
            .background(Capsule().fill(Palette.paper))
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// "+3 more" under a list that did not fit.
struct MoreLine: View {
    let count: Int
    let lang: String
    var size: CGFloat = 11

    var body: some View {
        Text(L10n.t("more", lang).replacingOccurrences(of: "{n}", with: String(count)))
            .font(Typo.text(size, .medium))
            .foregroundStyle(Palette.inkSoft)
            .lineLimit(1)
    }
}

/// What a widget says when it has nothing to draw from.
struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.text(12, .medium))
            .foregroundStyle(Palette.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Every widget sits on a card (.card: --paper-dim).
    func cardBackground() -> some View {
        containerBackground(for: .widget) { Palette.paperDim }
    }
}
