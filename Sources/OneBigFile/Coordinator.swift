import AppKit

final class Coordinator: NSObject, NSTextViewDelegate, EditorCoordinating {
    private let appState: AppState
    private weak var textView: OBFTextView?
    private var pendingRefresh: DispatchWorkItem?
    private var isLoading = false
    private var lastSyncedSelection = NSRange(location: NSNotFound, length: 0)
    private var highlightedMatch: NSRange?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func attach(textView: OBFTextView) {
        self.textView = textView
        textView.delegate = self
        textView.onInsertNewline = { [weak self] in
            self?.handleInsertNewline() ?? false
        }
        textView.onCommand = { [weak self] command in
            self?.handle(command: command)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )
        // Keep the document view exactly as wide as the scroll view's visible
        // area — SwiftUI layout does not propagate this reliably through
        // autoresizing, and a wider text view would stop lines from wrapping.
        if let scrollView = textView.enclosingScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipViewBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }
        syncTextViewWidth()
    }

    @objc private func clipViewBoundsChanged(_ note: Notification) {
        syncTextViewWidth()
    }

    private func syncTextViewWidth() {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let width = scrollView.contentSize.width
        guard width > 0, abs(textView.frame.width - width) > 0.25 else { return }
        textView.frame.size.width = width
    }

    // MARK: - Loading / saving

    func loadDocument() {
        guard let textView, let storage = textView.textStorage else { return }
        isLoading = true
        highlightedMatch = nil
        let markdown = appState.store.load()
        storage.setAttributedString(render(markdown: markdown))
        isLoading = false
        textView.typingAttributes = styleAttributes(for: nil)
        rebuildOutline()
    }

    func saveNow() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        guard let storage = textView?.textStorage else { return }
        appState.store.save(markdown: serialize(storage: storage))
    }

    private func serialize(storage: NSTextStorage) -> String {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return "" }
        var lines: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            var line = substring ?? ""
            if content.length > 0,
               let level = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int {
                if level == 1 {
                    line = "# " + line
                } else if level == 2 {
                    line = "## " + line
                }
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private func render(markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = parseLines(markdown)
        for (index, line) in lines.enumerated() {
            result.append(NSAttributedString(string: line.text, attributes: styleAttributes(for: line.level)))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: styleAttributes(for: nil)))
            }
        }
        return result
    }

    private func parseLines(_ markdown: String) -> [(text: String, level: Int?)] {
        var lines: [(String, Int?)] = []
        (markdown as NSString).enumerateLines { rawLine, _ in
            var line = rawLine
            var level: Int? = nil
            if line == "#" {
                level = 1
                line = ""
            } else if line.hasPrefix("# ") {
                level = 1
                line = String(line.dropFirst(2))
            } else if line == "##" {
                level = 2
                line = ""
            } else if line.hasPrefix("## ") {
                level = 2
                line = String(line.dropFirst(3))
            }
            lines.append((line, level))
        }
        return lines
    }

    // MARK: - Styling

    func styleAttributes(for level: Int?) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: OBFTheme.textNS,
            .paragraphStyle: paragraph
        ]
        switch level {
        case 1:
            attributes[.font] = appState.h1Font
            attributes[.foregroundColor] = OBFTheme.h1TextNS
        case 2:
            attributes[.font] = appState.h2Font
            paragraph.headIndent = 24
        default:
            attributes[.font] = appState.bodyFont
        }
        if let level {
            attributes[.obfHeadingLevel] = level
        }
        return attributes
    }

    /// Re-applies fonts / colors / indentation to the paragraphs intersecting `range`.
    /// The OBFHeadingLevel attribute is kept on paragraph content only, never on the
    /// trailing newline, so newly created empty paragraphs always start as body text.
    private func applyStyles(in range: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard clamped.length > 0 else { return }
        storage.beginEditing()
        ns.enumerateSubstrings(in: clamped, options: .byParagraphs) { _, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            var level: Int? = nil
            if content.length > 0 {
                level = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int
            }
            if content.length > 0 {
                storage.setAttributes(self.styleAttributes(for: level), range: content)
            }
            let terminatorLength = enclosing.length - content.length
            if terminatorLength > 0 {
                // Newline characters always carry body styling (never heading
                // font or marker), so attributes can never leak across
                // paragraphs through typing-attribute derivation at boundaries.
                storage.setAttributes(
                    self.styleAttributes(for: nil),
                    range: NSRange(location: NSMaxRange(enclosing) - terminatorLength, length: terminatorLength)
                )
            }
        }
        storage.endEditing()
    }

    /// Semantic paragraph range for a caret position: unlike
    /// `NSString.paragraphRange(for:)`, a caret right after a newline
    /// (an empty paragraph, including the empty trailing one) belongs to
    /// THAT paragraph, not to the previous one.
    private func paragraphRange(at location: Int) -> NSRange {
        guard let storage = textView?.textStorage else {
            return NSRange(location: max(location, 0), length: 0)
        }
        let ns = storage.string as NSString
        let length = ns.length
        let clamped = min(max(location, 0), length)
        var start = clamped
        while start > 0 && ns.character(at: start - 1) != 0x0A { start -= 1 }
        var end = clamped
        while end < length && ns.character(at: end) != 0x0A { end += 1 }
        if end < length { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private func syncTypingAttributes() {
        guard let textView, let storage = textView.textStorage else { return }
        guard storage.length > 0 else {
            textView.typingAttributes = styleAttributes(for: nil)
            return
        }
        let paragraph = paragraphRange(at: textView.selectedRange().location)
        let content = contentRange(of: paragraph)
        let level = content.length > 0
            ? storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int
            : nil
        textView.typingAttributes = styleAttributes(for: level)
    }

    // MARK: - Storage observation

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard !isLoading else { return }
        guard let textView, let storage = textView.textStorage else { return }
        if storage.editedMask.contains(.editedCharacters), storage.length > 0 {
            let edited = storage.editedRange
            if edited.location != NSNotFound {
                let bounds = NSRange(location: 0, length: storage.length)
                let bounded = NSIntersectionRange(edited, bounds)
                let affected: NSRange
                if bounded.length > 0 {
                    affected = (storage.string as NSString).paragraphRange(for: bounded)
                } else {
                    affected = paragraphRange(at: edited.location)
                }
                // Attribute mutations re-enter AppKit's edit handling
                // mid-flight: setting them synchronously from this
                // notification leaves stale glyphs on screen (a line joined
                // with the previous one appears duplicated until the next
                // full redraw). Defer to the next run-loop turn, when the
                // edit has completed. The dropped match highlight (a plain
                // background attribute) is re-applied by the next
                // selectCurrentMatch / updateFindMatches.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.clearMatchHighlight()
                    self.applyStyles(in: affected)
                    self.syncTypingAttributes()
                    // AppKit's incremental redraw occasionally leaves stale
                    // pixels when content shifts by a line of a different
                    // height (e.g. after an H1 line was deleted). A full
                    // repaint one tick after every edit is imperceptible and
                    // guarantees no ghost survives.
                    self.textView?.needsDisplay = true
                }
            }
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshNow()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func refreshNow() {
        rebuildOutline()
        if appState.findVisible {
            updateFindMatches(resetIndex: false)
        }
        saveNow()
    }

    // MARK: - Outline

    private func rebuildOutline() {
        guard let storage = textView?.textStorage else { return }
        let ns = storage.string as NSString
        guard ns.length > 0 else {
            appState.outline = []
            return
        }
        var items: [OutlineItem] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            guard content.length > 0,
                  let level = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int else { return }
            items.append(OutlineItem(title: substring ?? "", level: level, range: enclosing))
        }
        appState.outline = items
    }

    func scrollToOutline(_ item: OutlineItem) {
        guard let textView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              storage.length > 0 else { return }
        let location = min(item.range.location, storage.length - 1)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        layoutManager.ensureLayout(for: container)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        textView.scroll(NSPoint(x: 0, y: max(0, rect.minY - 12)))
        textView.window?.makeFirstResponder(textView)
        syncTypingAttributes()
    }

    // MARK: - Heading toggle

    func setHeadingLevel(_ level: Int) {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        let target: NSRange
        if selection.length > 0 {
            let bounded = NSIntersectionRange(selection, NSRange(location: 0, length: ns.length))
            let reference = bounded.length > 0
                ? bounded
                : NSRange(location: min(selection.location, ns.length - 1), length: 0)
            target = ns.paragraphRange(for: reference)
        } else {
            target = paragraphRange(at: min(selection.location, ns.length))
        }

        var paragraphs: [NSRange] = []
        if target.length > 0 {
            ns.enumerateSubstrings(in: target, options: .byParagraphs) { _, _, enclosing, _ in
                if enclosing.length > 0 {
                    paragraphs.append(enclosing)
                }
            }
        }

        var styledAny = false
        storage.beginEditing()
        for paragraph in paragraphs {
            let content = contentRange(of: paragraph)
            guard content.length > 0 else { continue }
            styledAny = true
            let current = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int
            if level == 0 || current == level {
                storage.removeAttribute(.obfHeadingLevel, range: paragraph)
            } else {
                storage.addAttribute(.obfHeadingLevel, value: level, range: paragraph)
            }
        }
        storage.endEditing()

        if !styledAny {
            // Empty paragraph: nothing to restyle, so prepare typing
            // attributes — the text the user is about to type gets the level.
            textView.typingAttributes = styleAttributes(for: level == 0 ? nil : level)
        }

        applyStyles(in: target)
        if styledAny {
            syncTypingAttributes()
        }
        scheduleRefresh()
    }

    private func handle(command: OBFCommand) {
        switch command {
        case .find:
            appState.showFindBar()
        case .heading(let level):
            setHeadingLevel(level)
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        zoom(by: 1)
    }

    func zoomOut() {
        zoom(by: -1)
    }

    private func zoom(by delta: Double) {
        appState.bodyPointSize += delta
        guard let textView else { return }
        textView.font = appState.bodyFont
        if let storage = textView.textStorage, storage.length > 0 {
            applyStyles(in: NSRange(location: 0, length: storage.length))
        }
        syncTypingAttributes()
    }

    // MARK: - Enter at end of heading

    /// Returns true when the newline was handled here: Enter at the end of a
    /// heading paragraph inserts a plain newline styled as body text.
    private func handleInsertNewline() -> Bool {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location <= storage.length else { return false }
        let ns = storage.string as NSString
        let location = min(selection.location, ns.length - 1)
        let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
        let content = contentRange(of: paragraph)
        guard content.length > 0,
              storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int != nil,
              selection.location == NSMaxRange(content) else { return false }
        textView.typingAttributes = styleAttributes(for: nil)
        textView.insertText("\n", replacementRange: selection)
        textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        textView.typingAttributes = styleAttributes(for: nil)
        return true
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView else { return }
        let selection = textView.selectedRange()
        guard selection != lastSyncedSelection else { return }
        lastSyncedSelection = selection
        syncTypingAttributes()
    }

    // MARK: - Find

    func updateFindMatches() {
        updateFindMatches(resetIndex: true)
    }

    private func updateFindMatches(resetIndex: Bool) {
        guard let storage = textView?.textStorage else { return }
        clearMatchHighlight()
        let query = appState.findQuery
        var ranges: [NSRange] = []
        if !query.isEmpty {
            let ns = storage.string as NSString
            var searchStart = 0
            while searchStart < ns.length {
                let found = ns.range(
                    of: query,
                    options: .caseInsensitive,
                    range: NSRange(location: searchStart, length: ns.length - searchStart)
                )
                if found.location == NSNotFound || found.length == 0 { break }
                ranges.append(found)
                searchStart = NSMaxRange(found)
            }
        }
        appState.matches = ranges
        if resetIndex {
            appState.currentMatchIndex = 0
        } else {
            appState.currentMatchIndex = ranges.isEmpty ? 0 : min(appState.currentMatchIndex, ranges.count - 1)
        }
        if !ranges.isEmpty {
            selectCurrentMatch()
        }
    }

    func findNext() {
        guard !appState.matches.isEmpty else { return }
        appState.currentMatchIndex = (appState.currentMatchIndex + 1) % appState.matches.count
        selectCurrentMatch()
    }

    func findPrev() {
        guard !appState.matches.isEmpty else { return }
        appState.currentMatchIndex = (appState.currentMatchIndex - 1 + appState.matches.count) % appState.matches.count
        selectCurrentMatch()
    }

    private func selectCurrentMatch() {
        guard appState.findVisible else { return }
        guard let textView,
              let storage = textView.textStorage,
              appState.currentMatchIndex < appState.matches.count else { return }
        let range = appState.matches[appState.currentMatchIndex]
        guard NSMaxRange(range) <= storage.length else { return }
        // The match is highlighted with a background attribute in the text
        // storage: it keeps selectionNS regardless of focus (AppKit would
        // otherwise draw the selection with system colors), it shifts with
        // edits like any attribute, and the text selection itself is left
        // alone so no "stuck" selection can survive closing the find bar.
        clearMatchHighlight()
        storage.addAttribute(.backgroundColor, value: OBFTheme.selectionNS, range: range)
        highlightedMatch = range
        textView.scrollRangeToVisible(range)
    }

    /// Callers must wrap edits in begin/end editing (or tolerate the
    /// resulting notifications): removing the attribute fires a storage
    /// notification of its own, and highlightedMatch is nil by then.
    private func clearMatchHighlight() {
        guard let storage = textView?.textStorage,
              let range = highlightedMatch else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        if clamped.length > 0 {
            storage.removeAttribute(.backgroundColor, range: clamped)
        }
        highlightedMatch = nil
    }

    func clearFindHighlight() {
        guard highlightedMatch != nil, let storage = textView?.textStorage else { return }
        storage.beginEditing()
        clearMatchHighlight()
        storage.endEditing()
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Test hook: the live text view, for --replay modes that drive the real
    /// app window.
    var debugTextView: OBFTextView? { textView }

    // MARK: - Utilities

    /// Paragraph range without its trailing newline character.
    private func contentRange(of paragraph: NSRange) -> NSRange {
        guard let storage = textView?.textStorage,
              paragraph.length > 0,
              NSMaxRange(paragraph) <= storage.length else { return paragraph }
        let ns = storage.string as NSString
        let last = ns.character(at: NSMaxRange(paragraph) - 1)
        if last == 0x0A || last == 0x0D {
            return NSRange(location: paragraph.location, length: paragraph.length - 1)
        }
        return paragraph
    }
}
