import AppKit
import SwiftUI

extension NSAttributedString.Key {
    static let obfHeadingLevel = NSAttributedString.Key("OBFHeadingLevel")
    /// 1 = task (todo), 2 = done. Set on paragraph content only, like
    /// obfHeadingLevel; the trailing newline never carries it.
    static let obfTaskState = NSAttributedString.Key("OBFTaskState")
    /// Creation date of a task, "yyyy-MM-dd". Serialized into the markdown
    /// as an HTML comment right after the task marker; never shown in the
    /// editor itself, only in the sidebar's task list.
    static let obfTaskCreated = NSAttributedString.Key("OBFTaskCreated")
    /// On the "-" of a list line ("- текст"): the bullet drawn in its
    /// place ("•", "◦", "▪" by nesting level). The document keeps "- ".
    static let obfBullet = NSAttributedString.Key("OBFBullet")
    /// URL of a detected link; Cmd+click opens it.
    static let obfLink = NSAttributedString.Key("OBFLink")
}

enum OBFCommand {
    case find
    case heading(Int)
    case task
    case taskDone
    case list
}

final class OBFTextView: NSTextView {
    var onInsertNewline: (() -> Bool)?
    var onDeleteBackward: (() -> Bool)?
    var onCommand: ((OBFCommand) -> Void)?

    override func insertNewline(_ sender: Any?) {
        if let onInsertNewline, onInsertNewline() {
            return
        }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if let onDeleteBackward, onDeleteBackward() {
            return
        }
        super.deleteBackward(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command], let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "f": onCommand?(.find); return true
            case "1": onCommand?(.heading(1)); return true
            case "2": onCommand?(.heading(2)); return true
            case "0": onCommand?(.heading(0)); return true
            case "3": onCommand?(.task); return true
            case "4": onCommand?(.taskDone); return true
            case "5": onCommand?(.list); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.25
        let clip = enclosingScrollView?.contentView
        let scrollY = clip?.bounds.origin.y ?? 0
        super.setFrameSize(newSize)
        updateColumnInsets()
        // A width change (the sidebar sliding in or out) re-insets the
        // column, and AppKit then scrolls to "reveal" the caret — the
        // document jumps. Keep the reader where they were instead. (Height
        // changes come from typing and keep AppKit's caret scrolling.)
        if widthChanged, let clip, abs(clip.bounds.origin.y - scrollY) > 0.5 {
            let maxY = max(0, frame.height - clip.bounds.height)
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: min(scrollY, maxY)))
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// Centers a text column of at most OBFTheme.textColumnWidth (never
    /// closer than 20 to the edges). The column's width is set explicitly
    /// instead of tracking the view: while the view resizes (the sidebar
    /// sliding), the column stays exactly the same width, so no line
    /// re-wraps and nothing jitters — only the inset moves, in half-point
    /// (one Retina pixel) steps so glyphs keep their pixel alignment.
    func updateColumnInsets() {
        let column = max(0, min(OBFTheme.textColumnWidth, frame.width - 40))
        if let textContainer {
            textContainer.widthTracksTextView = false
            if abs(textContainer.size.width - column) > 0.01 {
                textContainer.size = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        let horizontal = max(20, floor(frame.width - column) / 2)
        let inset = NSSize(width: horizontal, height: OBFTheme.textTopInset)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    // MARK: Sheet

    /// The sheet under the text column, in view coordinates: the column
    /// plus OBFTheme.paperPadding each side, from the style's top gap down
    /// past the bottom (the page never ends).
    var paperRect: NSRect {
        let x = max(8, textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0) - OBFTheme.paperPadding)
        let top = OBFTheme.paperTopGap
        return NSRect(x: x, y: top, width: max(0, bounds.width - 2 * x),
                      height: bounds.height - top + OBFTheme.paperCornerRadius + 40)
    }

    override func drawBackground(in rect: NSRect) {
        // Desk, then the sheet: lighter, a hairline border, rounded top
        // corners and a soft shadow.
        let theme = OBFTheme.theme
        theme.desk.setFill()
        rect.fill()
        let radius = OBFTheme.paperCornerRadius
        let path = NSBezierPath(roundedRect: paperRect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(theme.shadow)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        theme.paper.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        theme.paperBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: Links

    /// Cmd+click on a link opens it; a plain click edits text as usual.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let url = link(at: event.locationInWindow) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    /// With Cmd held over a link, the pointer becomes a hand.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateLinkCursor(event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateLinkCursor(event)
    }

    private func updateLinkCursor(_ event: NSEvent) {
        guard let window else { return }
        let location = event.type == .flagsChanged ? window.mouseLocationOutsideOfEventStream : event.locationInWindow
        if event.modifierFlags.contains(.command), link(at: location) != nil {
            NSCursor.pointingHand.set()
        } else if event.type == .flagsChanged, bounds.contains(convert(location, from: nil)) {
            NSCursor.iBeam.set()
        }
    }

    /// The link under a window point, if any.
    func link(at windowPoint: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let point = convert(windowPoint, from: nil)
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: inContainer, in: textContainer,
                                             fractionOfDistanceThroughGlyph: &fraction)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.contains(inContainer) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return nil }
        return storage.attribute(.obfLink, at: index, effectiveRange: nil) as? URL
    }

    override func layout() {
        super.layout()
        fitWidthToClipView()
    }

    /// Hard constraint: the text view is never wider than the visible area
    /// of its scroll view. SwiftUI's window setup leaves the document view
    /// at an intermediate, wider proposal (measured 1507 pt against a
    /// 907 pt clip view), and then long lines overflow the right edge until
    /// the first scroll re-syncs the width. Enforcing it at layout time
    /// makes the text wrap correctly from the very first frame. The text
    /// container insets (20/16) then act as strict left/right/top/bottom
    /// margins.
    private func fitWidthToClipView() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let width = clipView.bounds.width
        guard width > 0, abs(frame.width - width) > 0.25 else { return }
        frame.size.width = width
    }
}

protocol EditorCoordinating: AnyObject {
    func setHeadingLevel(_ level: Int)
    func toggleTask()
    func toggleTaskDone()
    func toggleList()
    func scrollToOutline(_ item: OutlineItem)
    func scrollToTask(_ item: SidebarTaskItem)
    func updateFindMatches()
    func findNext()
    func findPrev()
    func saveNow()
    func focusEditor()
    func zoomIn()
    func zoomOut()
    func clearFindHighlight()
    func clearSelection()
    /// Re-applies fonts and text layout after a typography setting changed.
    func applyTypography()
    /// Recomputes (or, when switched off, clears) the breadcrumb.
    func refreshBreadcrumb()
}

struct EditorView: NSViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: OBFTheme.textTopInset)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true

        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.backgroundColor = OBFTheme.deskNS
        textView.drawsBackground = true
        textView.insertionPointColor = OBFTheme.textNS
        textView.selectedTextAttributes = [
            .backgroundColor: OBFTheme.selectionNS,
            .foregroundColor: OBFTheme.textNS
        ]

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = OBFTheme.deskNS
        scrollView.borderType = .noBorder
        // Bit-blit copying of already-rendered content is the classic source
        // of ghost lines when text shifts by a line of a different height
        // (e.g. an H1 line is removed and everything below jumps up).
        scrollView.contentView.copiesOnScroll = false

        context.coordinator.attach(textView: textView)
        context.coordinator.loadDocument()
        appState.editor = context.coordinator
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Belt and braces alongside the clip-view bounds observer in
        // Coordinator: the document view must never be wider than the
        // visible area, otherwise long lines overflow instead of wrapping.
        guard let textView = nsView.documentView as? OBFTextView else { return }
        let width = nsView.contentSize.width
        if width > 0, abs(textView.frame.size.width - width) > 0.25 {
            textView.frame.size.width = width
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.saveNow()
    }
}
