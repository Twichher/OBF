import AppKit
import SwiftUI

enum OBFTheme {
    // Graphite dark: near-black neutral background, soft cool white text,
    // steel-blue selection, quiet divider.
    static let bgNS = NSColor(calibratedRed: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x14 / 255.0, alpha: 1)
    static let textNS = NSColor(calibratedRed: 0xC9 / 255.0, green: 0xCD / 255.0, blue: 0xD6 / 255.0, alpha: 1)
    static let borderNS = NSColor(calibratedRed: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x2C / 255.0, alpha: 1)
    static let selectionNS = NSColor(calibratedRed: 0x38 / 255.0, green: 0x50 / 255.0, blue: 0x6E / 255.0, alpha: 1)
    /// Floating panels (the sidebar tab list) — a step lighter than the
    /// background so they read as being above the content behind them.
    static let elevatedNS = NSColor(calibratedRed: 0x1B / 255.0, green: 0x1B / 255.0, blue: 0x22 / 255.0, alpha: 1)
    /// H1 text color — a bright amber so first-level headings stand out
    /// from body text and from H2.
    static let h1TextNS = NSColor(calibratedRed: 0xFF / 255.0, green: 0xB4 / 255.0, blue: 0x4D / 255.0, alpha: 1)

    static let bg = Color(nsColor: bgNS)
    static let text = Color(nsColor: textNS)
    static let border = Color(nsColor: borderNS)
    static let elevated = Color(nsColor: elevatedNS)

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

    /// Single place to change the app font. Applies to the editor, the
    /// sidebar and the find bar.
    static let fontName = "Georgia"

    static func font(size: CGFloat, bold: Bool) -> NSFont {
        let base = NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        guard bold else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }
}
