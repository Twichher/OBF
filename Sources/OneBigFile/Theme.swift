import AppKit
import SwiftUI

enum OBFTheme {
    /// The colour theme (Вид → Тема). Persisted.
    static var theme: ColorTheme = ColorTheme.named(UserDefaults.standard.string(forKey: "theme"))

    /// Window background around the sheet ("desk"); also the inset boxes
    /// of cards and modals.
    static var bgNS: NSColor { theme.desk }
    static var textNS: NSColor { theme.text }
    static var borderNS: NSColor { theme.border }
    static var selectionNS: NSColor { theme.selection }
    /// Floating panels and cards — a step apart from the background.
    static var elevatedNS: NSColor { theme.elevated }
    /// H1 text and the app's accent (checkboxes, "+", chosen options).
    static var h1TextNS: NSColor { theme.h1 }
    /// Done tasks and routine checkmarks.
    static var doneNS: NSColor { theme.done }
    /// Links in the text.
    static var linkNS: NSColor { theme.link }
    /// List bullets — quieter than the text.
    static var bulletNS: NSColor { theme.text.withAlphaComponent(0.55) }

    static var bg: Color { Color(nsColor: bgNS) }
    static var h1Text: Color { Color(nsColor: h1TextNS) }
    static var done: Color { Color(nsColor: doneNS) }
    static var text: Color { Color(nsColor: textNS) }
    static var border: Color { Color(nsColor: borderNS) }
    static var elevated: Color { Color(nsColor: elevatedNS) }
    static var selection: Color { Color(nsColor: selectionNS) }
    static var paperBorder: Color { Color(nsColor: theme.paperBorder) }
    /// Emphasised text (big titles): white on dark themes, ink on light.
    static var strong: Color { theme.isDark ? .white : Color(nsColor: theme.text.blended(withFraction: 0.5, of: .black) ?? theme.text) }
    /// Faint hover fill for buttons and rows.
    static var hover: Color { theme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05) }
    static var colorScheme: ColorScheme { theme.isDark ? .dark : .light }

    static let minBodySize: Double = 10
    static let maxBodySize: Double = 28
    static let defaultBodySize: Double = 14

    /// Fixed window layout. The window is not resizable (.contentSize), so
    /// these constants drive both the SwiftUI frames and the sidebar hit
    /// region the swipe monitor checks gesture locations against.
    static let windowWidth: CGFloat = 1200
    static let windowHeight: CGFloat = 800
    static let sidebarWidth: CGFloat = 260
    static let contentPadding: CGFloat = 16
    /// Gap between the editor and the floating sidebar card.
    static let sidebarGap: CGFloat = 12
    static let sidebarCornerRadius: CGFloat = 16
    /// Sliding the sidebar out and in (Cmd+S).
    static let sidebarAnimation = Animation.spring(response: 0.42, dampingFraction: 0.88)

    /// The sidebar card in window coordinates (origin bottom left): the
    /// layout is fixed, so hit tests can use it directly.
    static var sidebarFrame: CGRect {
        CGRect(x: windowWidth - contentPadding - sidebarWidth, y: contentPadding,
               width: sidebarWidth, height: windowHeight - contentPadding * 2 - paperTopGap)
    }

    /// Widest the text column gets; on a wider editor it is centered.
    /// Around 75 characters per line — comfortable for reading.
    static let textColumnWidth: CGFloat = 700
    /// Top/bottom margin of the text (inside the sheet, below its top
    /// edge).
    static let textTopInset: CGFloat = 28 + paperTopGap

    // The writing sheet: a band down the middle of the editor that scrolls
    // with the text — its top edge shows at the start of the document, the
    // sides sit on the darker desk.
    static var deskNS: NSColor { theme.desk }
    static var desk: Color { Color(nsColor: deskNS) }
    static var paperNS: NSColor { theme.paper }
    static var paper: Color { Color(nsColor: paperNS) }
    /// Sheet margin left and right of the text column.
    static let paperPadding: CGFloat = 48
    /// Desk visible above the sheet's top edge.
    static let paperTopGap: CGFloat = 18
    static let paperCornerRadius: CGFloat = 10

    /// The document font (Вид → Шрифт текста). Persisted.
    static var editorFont: EditorFont = EditorFont(
        rawValue: UserDefaults.standard.string(forKey: "editorFont") ?? "") ?? .newYork

    /// The interface font (sidebar, modals, find bar): the system font, or
    /// the document font. Persisted.
    static var uiFollowsEditor: Bool = UserDefaults.standard.bool(forKey: "uiFollowsEditor")

    /// Kept for places that name the font directly: the document font's
    /// family name.
    static var fontName: String { editorFont.familyName }

    /// A document font at `size`.
    static func font(size: CGFloat, bold: Bool) -> NSFont {
        editorFont.font(size: size, bold: bold)
    }

    /// AppKit counterpart of `ui(_:)`, for measuring and AppKit text views.
    static func uiNSFont(size: CGFloat, bold: Bool = false) -> NSFont {
        uiFollowsEditor
            ? editorFont.font(size: size, bold: bold)
            : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    /// Interface text at `size` in the chosen interface font.
    static func ui(_ size: CGFloat) -> Font {
        uiFollowsEditor ? Font(editorFont.font(size: size, bold: false)) : .system(size: size)
    }

    static func uiBold(_ size: CGFloat) -> Font {
        uiFollowsEditor ? Font(editorFont.font(size: size, bold: true)) : .system(size: size, weight: .semibold)
    }
}

/// Document fonts on offer. All ship with macOS.
enum EditorFont: String, CaseIterable, Identifiable {
    case georgia, newYork, charter, iowan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .georgia: return "Georgia"
        case .newYork: return "New York"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        }
    }

    var familyName: String {
        switch self {
        case .georgia: return "Georgia"
        case .newYork: return ".AppleSystemUIFontSerif"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        }
    }

    func font(size: CGFloat, bold: Bool) -> NSFont {
        switch self {
        case .newYork:
            // Apple's system serif is only reachable through the system
            // font's serif design.
            let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if let serif = base.fontDescriptor.withDesign(.serif) {
                return NSFont(descriptor: serif, size: size) ?? base
            }
            return base
        default:
            let base = NSFont(name: title == "Iowan Old Style" ? "IowanOldStyle-Roman" : familyName, size: size)
                ?? NSFont(name: familyName, size: size)
                ?? NSFont.systemFont(ofSize: size)
            guard bold else { return base }
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        }
    }
}

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

/// A colour theme: the background (desk and sheet), text, H1 / accent and
/// selection, plus the few colours derived for panels and states.
struct ColorTheme: Identifiable, Equatable {
    let id: String
    let title: String
    let isDark: Bool
    let desk: NSColor
    let paper: NSColor
    let paperBorder: NSColor
    let text: NSColor
    let h1: NSColor
    let selection: NSColor
    let elevated: NSColor
    let border: NSColor
    let link: NSColor
    let done: NSColor
    /// Opacity of the sheet's shadow.
    let shadow: CGFloat

    static func == (lhs: ColorTheme, rhs: ColorTheme) -> Bool { lhs.id == rhs.id }

    static func named(_ id: String?) -> ColorTheme {
        all.first { $0.id == id } ?? graphite
    }

    static let graphite = ColorTheme(
        id: "graphite", title: "Графит", isDark: true,
        desk: hex(0x0A0A0D), paper: hex(0x16161B), paperBorder: hex(0x2A2A31),
        text: hex(0xC9CDD6), h1: hex(0xFFB44D), selection: hex(0x38506E),
        elevated: hex(0x1B1B22), border: hex(0x26262C), link: hex(0x7FA8E0), done: hex(0x6FC28B), shadow: 0.55)

    static let all: [ColorTheme] = [
        graphite,
        ColorTheme(
            id: "midnight", title: "Полночь", isDark: true,
            desk: hex(0x080C16), paper: hex(0x111827), paperBorder: hex(0x243048),
            text: hex(0xD2DAEA), h1: hex(0x7DB3FF), selection: hex(0x2C4A7C),
            elevated: hex(0x162033), border: hex(0x223049), link: hex(0x8FD3E8), done: hex(0x6FCB9F), shadow: 0.6),
        ColorTheme(
            id: "tokyo", title: "Токио", isDark: true,
            desk: hex(0x13141D), paper: hex(0x1B1D2B), paperBorder: hex(0x2E3148),
            text: hex(0xC4CBEF), h1: hex(0xBB9AF7), selection: hex(0x3A4476),
            elevated: hex(0x222536), border: hex(0x2C3048), link: hex(0x7DCFFF), done: hex(0x9ECE6A), shadow: 0.55),
        ColorTheme(
            id: "forest", title: "Лес", isDark: true,
            desk: hex(0x0A100E), paper: hex(0x131B18), paperBorder: hex(0x24322C),
            text: hex(0xCFDDD4), h1: hex(0x8FD694), selection: hex(0x2E5245),
            elevated: hex(0x18231F), border: hex(0x223029), link: hex(0x86C5D8), done: hex(0xA6D98A), shadow: 0.55),
        ColorTheme(
            id: "coffee", title: "Кофе", isDark: true,
            desk: hex(0x110E0B), paper: hex(0x1C1814), paperBorder: hex(0x332B23),
            text: hex(0xE4D7C4), h1: hex(0xE8A55C), selection: hex(0x5A4430),
            elevated: hex(0x241F19), border: hex(0x2F2821), link: hex(0x9CC3D9), done: hex(0xA8C98A), shadow: 0.55),
        ColorTheme(
            id: "nord", title: "Север", isDark: true,
            desk: hex(0x20242C), paper: hex(0x2B303B), paperBorder: hex(0x3B4252),
            text: hex(0xD8DEE9), h1: hex(0x88C0D0), selection: hex(0x4C566A),
            elevated: hex(0x323845), border: hex(0x3B4252), link: hex(0x81A1C1), done: hex(0xA3BE8C), shadow: 0.45),
        ColorTheme(
            id: "paper", title: "Бумага (светлая)", isDark: false,
            desk: hex(0xE7E3DA), paper: hex(0xFBF9F5), paperBorder: hex(0xD8D2C6),
            text: hex(0x2E2B27), h1: hex(0xB4541E), selection: hex(0xCFE0F7),
            elevated: hex(0xF3F0EA), border: hex(0xDAD4C8), link: hex(0x2F6FB3), done: hex(0x3E8E5A), shadow: 0.12),
    ]
}
