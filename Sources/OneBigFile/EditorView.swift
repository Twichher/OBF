import AppKit
import SwiftUI

extension NSAttributedString.Key {
    static let obfHeadingLevel = NSAttributedString.Key("OBFHeadingLevel")
    /// 1 = task (todo), 2 = done. Set on paragraph content only, like
    /// obfHeadingLevel; the trailing newline never carries it.
    static let obfTaskState = NSAttributedString.Key("OBFTaskState")
}

enum OBFCommand {
    case find
    case heading(Int)
    case task
    case taskDone
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
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
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
    func scrollToOutline(_ item: OutlineItem)
    func updateFindMatches()
    func findNext()
    func findPrev()
    func saveNow()
    func focusEditor()
    func zoomIn()
    func zoomOut()
    func clearFindHighlight()
    func clearSelection()
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
        textView.textContainerInset = NSSize(width: 20, height: 16)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true

        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.backgroundColor = OBFTheme.bgNS
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
        scrollView.backgroundColor = OBFTheme.bgNS
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
