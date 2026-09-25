import AppKit

final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate, EditorCoordinating {
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
        // Draws list bullets in place of the "-" characters.
        textView.layoutManager?.delegate = self
        textView.onInsertNewline = { [weak self] in
            self?.handleInsertNewline() ?? false
        }
        textView.onDeleteBackward = { [weak self] in
            self?.handleDeleteBackward() ?? false
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
        updateBreadcrumb()
    }

    private func syncTextViewWidth() {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let width = scrollView.contentSize.width
        guard width > 0, abs(textView.frame.width - width) > 0.25 else { return }
        textView.frame.size.width = width
    }

    // MARK: - Loading / saving

    /// Creation dates are stored as plain "yyyy-MM-dd" strings so the
    /// markdown comment stays human-readable and timezone-free.
    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func loadDocument() {
        guard let textView, let storage = textView.textStorage else { return }
        isLoading = true
        highlightedMatch = nil
        let markdown = appState.store.load()
        storage.setAttributedString(render(markdown: markdown))
        isLoading = false
        // Lists, indents and links are derived from the text itself.
        if storage.length > 0 {
            applyStyles(in: NSRange(location: 0, length: storage.length))
        }
        textView.typingAttributes = styleAttributes(for: nil)
        rebuildOutline()
    }

    func saveNow() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        guard let storage = textView?.textStorage else { return }
        appState.store.save(markdown: serialize(storage: storage))
    }

    func serialize(storage: NSTextStorage) -> String {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return "" }
        var lines: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            var line = substring ?? ""
            if content.length > 0,
               let task = storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int {
                // The checkbox is presentation-only: drop its character and
                // store the standard markdown task marker instead.
                if line.hasPrefix("\u{FFFC}") {
                    line = String(line.dropFirst())
                }
                let marker = task == 2 ? "- [x]" : "- [ ]"
                var prefix = marker
                if let created = storage.attribute(.obfTaskCreated, at: content.location, effectiveRange: nil) as? String {
                    prefix += " <!-- \(created) -->"
                }
                line = line.isEmpty ? prefix : prefix + " " + line
            } else if content.length > 0,
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

    func render(markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = parseLines(markdown)
        for (index, line) in lines.enumerated() {
            if let task = line.task {
                // The checkbox is a single attachment character at the
                // paragraph start; the gap after it is transparent padding
                // inside the attachment image itself.
                let attributes = styleAttributes(for: nil, task: task, created: line.created)
                var attachmentAttributes = attributes
                attachmentAttributes[.attachment] = checkboxAttachment(done: task == 2)
                result.append(NSAttributedString(string: "\u{FFFC}", attributes: attachmentAttributes))
                result.append(NSAttributedString(string: line.text, attributes: attributes))
            } else {
                result.append(NSAttributedString(string: line.text, attributes: styleAttributes(for: line.level)))
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: styleAttributes(for: nil)))
            }
        }
        return result
    }

    private func parseLines(_ markdown: String) -> [(text: String, level: Int?, task: Int?, created: String?)] {
        var lines: [(String, Int?, Int?, String?)] = []
        (markdown as NSString).enumerateLines { rawLine, _ in
            var line = rawLine
            var level: Int? = nil
            var task: Int? = nil
            var created: String? = nil
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
            } else if line == "- [ ]" || line == "- [x]" || line == "- [X]" {
                task = line == "- [ ]" ? 1 : 2
                line = ""
            } else if line.hasPrefix("- [ ] ") {
                task = 1
                line = String(line.dropFirst(6))
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                task = 2
                line = String(line.dropFirst(6))
            }
            if task != nil, line.hasPrefix("<!--"),
               let close = line.range(of: "-->") {
                // Creation date metadata: "- [ ] <!-- 2026-09-21 --> Текст".
                // The comment round-trips through save/load but is never
                // rendered in the editor.
                let raw = line[line.index(line.startIndex, offsetBy: 4)..<close.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty {
                    created = raw
                }
                line = String(line[close.upperBound...])
                if line.hasPrefix(" ") {
                    line = String(line.dropFirst())
                }
            }
            lines.append((line, level, task, created))
        }
        return lines
    }

    // MARK: - Styling

    /// Total width the checkbox occupies, including the gap before the text.
    /// Wrapped lines of a task align to exactly this indent.
    private var checkboxTotalWidth: CGFloat {
        ceil(appState.bodyFont.pointSize * 0.85) + 6
    }

    /// Cache by (done, font size); zooming restyles the whole document, so
    /// new sizes appear then.
    private var checkboxImageCache: [Int: NSImage] = [:]

    private func checkboxAttachment(done: Bool) -> NSTextAttachment {
        let font = appState.bodyFont
        let key = (done ? 100_000 : 0) + Int(font.pointSize * 10)
        if checkboxImageCache[key] == nil {
            let side = ceil(font.pointSize * 0.85)
            let gap: CGFloat = 6
            let image = NSImage(size: NSSize(width: side + gap, height: side), flipped: false) { _ in
                let inset: CGFloat = 0.75
                let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
                let outline = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
                outline.lineWidth = 1.2
                OBFTheme.textNS.setStroke()
                outline.stroke()
                if done {
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: side * 0.24, y: side * 0.52))
                    check.line(to: NSPoint(x: side * 0.44, y: side * 0.30))
                    check.line(to: NSPoint(x: side * 0.78, y: side * 0.70))
                    check.lineWidth = 1.6
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    OBFTheme.textNS.setStroke()
                    check.stroke()
                }
                return true
            }
            checkboxImageCache[key] = image
        }
        let attachment = NSTextAttachment()
        attachment.image = checkboxImageCache[key]
        // Attachments sit on the baseline; lift the box so it is vertically
        // centered on the cap height of the surrounding text.
        let side = ceil(font.pointSize * 0.85)
        let y = round((font.capHeight - side) / 2)
        attachment.bounds = NSRect(x: 0, y: y, width: checkboxTotalWidth, height: side)
        return attachment
    }

    func styleAttributes(for level: Int?, task: Int? = nil, created: String? = nil) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        // Air between lines and paragraphs; lineSpacing (added below each
        // line) keeps the caret its normal height.
        let size = CGFloat(appState.bodyPointSize)
        paragraph.lineSpacing = round(size * 0.3)
        paragraph.paragraphSpacing = round(size * 0.15)
        // Uniform tab stops: nested lines ("\t- …") step in evenly.
        paragraph.tabStops = []
        paragraph.defaultTabInterval = Self.indentStep
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: OBFTheme.textNS,
            .paragraphStyle: paragraph
        ]
        switch level {
        case 1:
            attributes[.font] = appState.h1Font
            attributes[.foregroundColor] = OBFTheme.h1TextNS
            // A heading belongs to the text below it: more room above.
            // Modest, since documents already separate sections with
            // blank lines.
            paragraph.paragraphSpacingBefore = round(size * 0.5)
            paragraph.paragraphSpacing = round(size * 0.2)
        case 2:
            attributes[.font] = appState.h2Font
            paragraph.headIndent = 24
            paragraph.paragraphSpacingBefore = round(size * 0.4)
            paragraph.paragraphSpacing = round(size * 0.15)
        default:
            attributes[.font] = appState.bodyFont
        }
        if let level {
            attributes[.obfHeadingLevel] = level
        }
        if let task {
            // Hanging indent: wrapped lines align with the text after the
            // checkbox. Spacing keeps tasks visually separated from the
            // paragraphs above and below.
            paragraph.firstLineHeadIndent = 0
            paragraph.headIndent = checkboxTotalWidth
            paragraph.paragraphSpacingBefore = 6
            paragraph.paragraphSpacing = 6
            attributes[.obfTaskState] = task
            if let created {
                attributes[.obfTaskCreated] = created
            }
            if task == 2 {
                attributes[.foregroundColor] = OBFTheme.textNS.withAlphaComponent(0.45)
            }
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
        // setAttributes below replaces every attribute in the restyled
        // paragraphs, so a match highlight intersecting them no longer
        // exists in the storage — forget it before it is re-applied.
        if let highlighted = highlightedMatch,
           NSIntersectionRange(highlighted, clamped).length > 0 {
            highlightedMatch = nil
        }
        storage.beginEditing()
        ns.enumerateSubstrings(in: clamped, options: .byParagraphs) { _, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            var level: Int? = nil
            var task: Int? = nil
            var created: String? = nil
            if content.length > 0 {
                level = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int
                task = storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int
                created = storage.attribute(.obfTaskCreated, at: content.location, effectiveRange: nil) as? String
            }
            if task != nil, content.length > 0 {
                if ns.character(at: content.location) == 0xFFFC {
                    // A paragraph is either a heading or a task; the task
                    // wins if both markers somehow coexist.
                    if level != nil {
                        storage.removeAttribute(.obfHeadingLevel, range: enclosing)
                        level = nil
                    }
                } else {
                    // A task without its checkbox character is a broken
                    // task (the character was deleted): heal by dropping
                    // the marker, restyling the paragraph as body text.
                    storage.removeAttribute(.obfTaskState, range: enclosing)
                    storage.removeAttribute(.obfTaskCreated, range: enclosing)
                    task = nil
                    created = nil
                }
            }
            if content.length > 0 {
                storage.setAttributes(self.styleAttributes(for: level, task: task, created: created), range: content)
                if level == nil && task == nil {
                    self.decorateList(content, in: storage)
                }
                self.decorateLinks(content, in: storage)
                if let task {
                    // setAttributes above wipes the attachment attribute;
                    // put the checkbox image back, sized to the current font.
                    storage.addAttribute(
                        .attachment,
                        value: self.checkboxAttachment(done: task == 2),
                        range: NSRange(location: content.location, length: 1)
                    )
                }
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
        let task = content.length > 0
            ? storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int
            : nil
        textView.typingAttributes = styleAttributes(for: level, task: task)
    }

    // MARK: - Storage observation

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard !isLoading else { return }
        guard let textView, let storage = textView.textStorage else { return }
        // Only character edits schedule a refresh. Attribute-only edits
        // (restyling, the find highlight itself) change no content, and
        // scheduling from them made the debounced refresh re-apply the
        // highlight and scroll back to the match every 0.5 s — an endless
        // loop that fought the user's scrolling.
        guard storage.editedMask.contains(.editedCharacters) else { return }
        if storage.length > 0 {
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
                // edit has completed. The match highlight dropped by
                // restyling is re-applied right here (without scrolling),
                // so it never visibly disappears after an edit.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.updateTypingHint()
                    self.applyStyles(in: affected)
                    self.syncTypingAttributes()
                    if self.appState.findVisible {
                        self.updateFindMatches(resetIndex: false, scroll: false)
                    }
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

    /// After a character edit, marks the task under the caret as "being
    /// typed" (its sidebar card wiggles and shows a placeholder) — or
    /// clears the mark when the caret is anywhere else. Runs one turn
    /// after the edit, when the selection has settled: this keeps Enter
    /// pressed inside a task from marking the OLD task, since the caret
    /// has already moved to the new plain line.
    private func updateTypingHint() {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let paragraph = paragraphRange(at: textView.selectedRange().location)
        let content = contentRange(of: paragraph)
        var location: Int? = nil
        if content.length > 0,
           storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) != nil {
            location = paragraph.location
        }
        if appState.editingTaskLocation != location {
            appState.editingTaskLocation = location
        }
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
        appState.editingTaskLocation = nil
        if appState.findVisible {
            // No scrolling here: this fires 0.5 s after the last edit, when
            // the user may already have scrolled away from the match.
            updateFindMatches(resetIndex: false, scroll: false)
        }
        saveNow()
    }

    // MARK: - Outline

    private func rebuildOutline() {
        guard let storage = textView?.textStorage else { return }
        let ns = storage.string as NSString
        guard ns.length > 0 else {
            appState.outline = []
            appState.updateTasks([])
            return
        }
        var items: [OutlineItem] = []
        var tasks: [SidebarTaskItem] = []
        var currentH1: String?
        var currentH2: String?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            guard content.length > 0 else { return }
            if let level = storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) as? Int {
                // Tabs or spaces typed before a heading indent it in the
                // text only; the outline, breadcrumb and task headers show
                // the bare title.
                let title = (substring ?? "").trimmingCharacters(in: .whitespaces)
                items.append(OutlineItem(title: title, level: level, range: enclosing))
                // Headings above a task become its header in the
                // "Задания" tab; a new H1 resets the H2 below it.
                if level == 1 {
                    currentH1 = title
                    currentH2 = nil
                } else {
                    currentH2 = title
                }
                return
            }
            guard let state = storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int else { return }
            var text = substring ?? ""
            if text.hasPrefix("\u{FFFC}") {
                text = String(text.dropFirst())
            }
            let created = storage.attribute(.obfTaskCreated, at: content.location, effectiveRange: nil) as? String
            let h1 = currentH1.flatMap { $0.isEmpty ? nil : $0 }
            let h2 = currentH2.flatMap { $0.isEmpty ? nil : $0 }
            // The uid is provisional; AppState.updateTasks assigns the
            // stable identity used for sidebar animations.
            tasks.append(SidebarTaskItem(uid: 0, text: text, done: state == 2, created: created, h1: h1, h2: h2, range: enclosing))
        }
        // Newest first inside each group; tasks without a recorded date
        // sink to the bottom of their group.
        let newestFirst: (SidebarTaskItem, SidebarTaskItem) -> Bool = { lhs, rhs in
            let l = lhs.created ?? ""
            let r = rhs.created ?? ""
            if l != r { return l > r }
            return lhs.range.location > rhs.range.location
        }
        appState.outline = items
        updateBreadcrumb()
        updateCurrentHeading()
        appState.updateTasks(tasks.filter { !$0.done }.sorted(by: newestFirst)
            + tasks.filter { $0.done }.sorted(by: newestFirst))
    }

    func scrollToTask(_ item: SidebarTaskItem) {
        scrollTo(location: item.range.location)
    }

    func scrollToOutline(_ item: OutlineItem) {
        scrollTo(location: item.range.location)
    }

    private func scrollTo(location: Int) {
        guard let textView,
              let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              storage.length > 0 else { return }
        let location = min(location, storage.length - 1)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        layoutManager.ensureLayout(for: container)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        // The heading lands just below the pinned breadcrumb bar.
        let bar = appState.showBreadcrumb ? Self.breadcrumbHeight : 0
        textView.scroll(NSPoint(x: 0, y: max(0, rect.minY + textView.textContainerOrigin.y - bar - 14)))
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
        applyMatchHighlight()
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
        case .task:
            toggleTask()
        case .taskDone:
            toggleTaskDone()
        case .list:
            toggleList()
        }
    }

    // MARK: - Lists

    /// Cmd+5: turns the selected plain lines into list items ("- " after
    /// their leading tabs), or — when all of them already are — back into
    /// plain lines. Headings and tasks are left alone. Goes through the
    /// text view's editing path, so one Cmd+Z undoes it.
    func toggleList() {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        var paragraphs: [NSRange] = []
        if selection.length > 0, ns.length > 0 {
            let bounded = NSIntersectionRange(selection, NSRange(location: 0, length: ns.length))
            ns.enumerateSubstrings(in: ns.paragraphRange(for: bounded), options: .byParagraphs) { _, _, enclosing, _ in
                paragraphs.append(enclosing)
            }
        } else {
            paragraphs = [paragraphRange(at: min(selection.location, ns.length))]
        }
        // Plain lines only: (content, index of the "-" slot, is an item).
        var lines: [(markerAt: Int, isItem: Bool)] = []
        for paragraph in paragraphs {
            let content = contentRange(of: paragraph)
            if content.length > 0,
               storage.attribute(.obfHeadingLevel, at: content.location, effectiveRange: nil) != nil
                || storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) != nil {
                continue
            }
            var tabs = 0
            while tabs < content.length, ns.character(at: content.location + tabs) == 0x09 { tabs += 1 }
            let markerAt = content.location + tabs
            let isItem = NSMaxRange(content) - markerAt >= 2
                && ns.character(at: markerAt) == 0x2D && ns.character(at: markerAt + 1) == 0x20
            lines.append((markerAt, isItem))
        }
        guard !lines.isEmpty else { NSSound.beep(); return }
        let removing = lines.allSatisfy(\.isItem)
        var start = selection.location
        var end = NSMaxRange(selection)
        // Bottom-up, so earlier positions stay valid.
        for line in lines.reversed() where removing || !line.isItem {
            let range = NSRange(location: line.markerAt, length: removing ? 2 : 0)
            let replacement = removing ? "" : "- "
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { continue }
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: styleAttributes(for: nil)))
            textView.didChangeText()
            let delta = replacement.utf16.count - range.length
            func shift(_ position: Int) -> Int {
                if removing {
                    return position <= line.markerAt ? position
                        : max(line.markerAt, position + delta)
                }
                return position >= line.markerAt ? position + delta : position
            }
            start = shift(start)
            end = shift(end)
        }
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        syncTypingAttributes()
    }

    // MARK: - Tasks

    /// Cmd+3: toggles the task state of the paragraphs intersecting the
    /// selection. A task paragraph starts with a checkbox character (a text
    /// attachment whose image width includes the gap before the text);
    /// markdown-wise it is stored as "- [ ]" / "- [x]". A paragraph is
    /// either a heading or a task — toggling one clears the other.
    func toggleTask() {
        guard let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        let target: NSRange
        if selection.length > 0, ns.length > 0 {
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
        if paragraphs.isEmpty {
            // Empty document or an empty paragraph.
            paragraphs = [NSRange(location: min(selection.location, ns.length), length: 0)]
        }

        var caretDelta = 0
        storage.beginEditing()
        // Last paragraph first: character insertions/deletions shift the
        // ranges of everything below.
        for paragraph in paragraphs.reversed() {
            let content = contentRange(of: paragraph)
            let state = content.length > 0
                ? storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int
                : nil
            if state != nil {
                // Remove the task: drop the checkbox character, keep the text.
                if ns.character(at: content.location) == 0xFFFC {
                    storage.deleteCharacters(in: NSRange(location: content.location, length: 1))
                    storage.removeAttribute(
                        .obfTaskState,
                        range: NSRange(location: paragraph.location, length: max(paragraph.length - 1, 0))
                    )
                    storage.removeAttribute(
                        .obfTaskCreated,
                        range: NSRange(location: paragraph.location, length: max(paragraph.length - 1, 0))
                    )
                } else {
                    storage.removeAttribute(.obfTaskState, range: paragraph)
                    storage.removeAttribute(.obfTaskCreated, range: paragraph)
                }
                if paragraph.location <= selection.location {
                    caretDelta -= 1
                }
            } else {
                if paragraph.length > 0 {
                    storage.removeAttribute(.obfHeadingLevel, range: paragraph)
                }
                storage.insert(
                    NSAttributedString(string: "\u{FFFC}", attributes: styleAttributes(for: nil, task: 1, created: Self.todayString())),
                    at: paragraph.location
                )
                storage.addAttribute(
                    .obfTaskState,
                    value: 1,
                    range: NSRange(location: paragraph.location, length: content.length + 1)
                )
                storage.addAttribute(
                    .obfTaskCreated,
                    value: Self.todayString(),
                    range: NSRange(location: paragraph.location, length: content.length + 1)
                )
                if paragraph.location <= selection.location {
                    caretDelta += 1
                }
            }
        }
        storage.endEditing()

        let caret = min(max(selection.location + caretDelta, 0), storage.length)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        applyStyles(in: NSRange(location: 0, length: storage.length))
        applyMatchHighlight()
        syncTypingAttributes()
        scheduleRefresh()
    }

    /// Cmd+4: toggles done state of the task under the selection.
    func toggleTaskDone() {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let ns = storage.string as NSString
        let selection = textView.selectedRange()
        let bounded = NSIntersectionRange(selection, NSRange(location: 0, length: ns.length))
        let reference = bounded.length > 0
            ? bounded
            : NSRange(location: min(selection.location, max(ns.length - 1, 0)), length: 0)
        let target = ns.paragraphRange(for: reference)

        var toggled = false
        storage.beginEditing()
        ns.enumerateSubstrings(in: target, options: .byParagraphs) { _, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let content = self.contentRange(of: enclosing)
            guard content.length > 0,
                  let state = storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int
            else { return }
            storage.addAttribute(.obfTaskState, value: state == 2 ? 1 : 2, range: enclosing)
            toggled = true
        }
        storage.endEditing()
        guard toggled else { return }
        applyStyles(in: target)
        applyMatchHighlight()
        scheduleRefresh()
    }

    /// Backspace with the caret immediately after the checkbox removes the
    /// task formatting but keeps the text.
    private func handleDeleteBackward() -> Bool {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location > 0, selection.location <= storage.length else { return false }
        let paragraph = paragraphRange(at: selection.location)
        let content = contentRange(of: paragraph)
        guard content.length > 1,
              storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) != nil,
              selection.location == content.location + 1 else { return false }
        storage.deleteCharacters(in: NSRange(location: content.location, length: 1))
        let updated = paragraphRange(at: content.location)
        storage.removeAttribute(.obfTaskState, range: updated)
        storage.removeAttribute(.obfTaskCreated, range: updated)
        textView.setSelectedRange(NSRange(location: content.location, length: 0))
        applyStyles(in: updated)
        syncTypingAttributes()
        return true
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
        applyMatchHighlight()
        syncTypingAttributes()
    }

    func applyTypography() {
        // Checkbox images are drawn in the theme's colours.
        checkboxImageCache.removeAll()
        if let textView {
            // Theme colours of the text view itself. textColor recolours the
            // whole text, so it must come before the restyle (zoom) below,
            // which puts the heading, link and bullet colours back.
            textView.textColor = OBFTheme.textNS
            textView.insertionPointColor = OBFTheme.textNS
            textView.selectedTextAttributes = [
                .backgroundColor: OBFTheme.selectionNS,
                .foregroundColor: OBFTheme.textNS
            ]
            textView.backgroundColor = OBFTheme.deskNS
            textView.enclosingScrollView?.backgroundColor = OBFTheme.deskNS
            textView.updateColumnInsets()
        }
        zoom(by: 0)
        textView?.needsDisplay = true
        updateBreadcrumb()
    }

    // MARK: - Lists and links

    /// Indent per nesting level (one leading tab).
    static let indentStep: CGFloat = 22
    /// Bullets by nesting level, cycling.
    static let bullets = ["•", "◦", "▪"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// A plain line "\t…\t- текст" is a list item: its "-" is drawn as a
    /// bullet and wrapped lines hang under the text. A tab-indented line
    /// without "- " keeps its indent on wrapped lines too. The text itself
    /// is never changed.
    private func decorateList(_ content: NSRange, in storage: NSTextStorage) {
        let ns = storage.string as NSString
        var tabs = 0
        while tabs < content.length, ns.character(at: content.location + tabs) == 0x09 {
            tabs += 1
        }
        let markerAt = content.location + tabs
        let isItem = content.length - tabs >= 2
            && ns.character(at: markerAt) == 0x2D && ns.character(at: markerAt + 1) == 0x20
        guard isItem || tabs > 0,
              let base = storage.attribute(.paragraphStyle, at: content.location, effectiveRange: nil) as? NSParagraphStyle,
              let paragraph = base.mutableCopy() as? NSMutableParagraphStyle else { return }
        var indent = CGFloat(tabs) * Self.indentStep
        if isItem {
            let bullet = Self.bullets[tabs % Self.bullets.count]
            storage.addAttributes([.obfBullet: bullet, .foregroundColor: OBFTheme.bulletNS],
                                  range: NSRange(location: markerAt, length: 1))
            indent += ((bullet + " ") as NSString).size(withAttributes: [.font: appState.bodyFont]).width
            // Items of one list sit closer together than paragraphs.
            paragraph.paragraphSpacing = round(CGFloat(appState.bodyPointSize) * 0.1)
        }
        paragraph.headIndent = indent
        storage.addAttribute(.paragraphStyle, value: paragraph, range: content)
    }

    /// Detected URLs get the link colour, a quiet underline and their URL
    /// (Cmd+click opens it, see OBFTextView).
    private func decorateLinks(_ content: NSRange, in storage: NSTextStorage) {
        guard let detector = Self.linkDetector else { return }
        for match in detector.matches(in: storage.string, range: content) {
            guard let url = match.url else { continue }
            storage.addAttributes([
                .foregroundColor: OBFTheme.linkNS,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: OBFTheme.linkNS.withAlphaComponent(0.35),
                .obfLink: url,
            ], range: match.range)
        }
    }

    /// Swaps the glyph of each "-" that carries a bullet attribute for the
    /// bullet's glyph (falling back to "•" when the font lacks it).
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let ns = storage.string as NSString
        var replaced: [CGGlyph]?
        for i in 0..<glyphRange.length {
            let index = charIndexes[i]
            guard index < ns.length, ns.character(at: index) == 0x2D,
                  let bullet = storage.attribute(.obfBullet, at: index, effectiveRange: nil) as? String
            else { continue }
            for candidate in [bullet, "•"] {
                var chars = Array(candidate.utf16)
                var glyph = CGGlyph(0)
                if CTFontGetGlyphsForCharacters(aFont as CTFont, &chars, &glyph, 1), glyph != 0 {
                    if replaced == nil {
                        replaced = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                    }
                    replaced?[i] = glyph
                    break
                }
            }
        }
        guard let replaced else { return 0 }
        replaced.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(buffer.baseAddress!, properties: props, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    // MARK: - Breadcrumb

    /// Height of the pinned breadcrumb bar over the editor.
    static let breadcrumbHeight: CGFloat = 30

    /// Finds the headings scrolled past: the last H1 and (under it) the
    /// last H2 that start above the text visible just below the bar.
    func refreshBreadcrumb() {
        updateBreadcrumb()
    }

    private func updateBreadcrumb() {
        guard appState.showBreadcrumb else {
            if appState.breadcrumb != nil { appState.breadcrumb = nil }
            return
        }
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage,
              let clip = textView.enclosingScrollView?.contentView else { return }
        var crumb: Breadcrumb?
        if storage.length > 0, clip.bounds.minY > 1 {
            let y = clip.bounds.minY - textView.textContainerOrigin.y + Self.breadcrumbHeight
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: container)
            let top = layoutManager.characterIndexForGlyph(at: glyph)
            let above = appState.outline.filter { $0.range.location < top }
            let h1 = above.last { $0.level == 1 }
            let h2 = above.last { $0.level == 2 && $0.range.location > (h1?.range.location ?? -1) }
            if h1 != nil || h2 != nil {
                crumb = Breadcrumb(h1: h1, h2: h2)
            }
        }
        if appState.breadcrumb != crumb {
            appState.breadcrumb = crumb
        }
    }

    // MARK: - Enter at end of heading

    /// Returns true when the newline was handled here: Enter at the end of a
    /// heading paragraph inserts a plain newline styled as body text, and
    /// Enter inside a task finishes it.
    private func handleInsertNewline() -> Bool {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location <= storage.length else { return false }
        let ns = storage.string as NSString
        let location = min(selection.location, ns.length - 1)
        let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
        let content = contentRange(of: paragraph)

        // Enter inside a task finishes it: the text after the caret (if
        // any) becomes a plain body paragraph without the indent. Enter on
        // an empty task (checkbox only) just removes the checkbox. Enter
        // before the checkbox falls through to the default newline.
        if content.length > 0,
           storage.attribute(.obfTaskState, at: content.location, effectiveRange: nil) as? Int != nil,
           selection.location > content.location {
            if content.length == 1 {
                let start = content.location
                storage.deleteCharacters(in: NSRange(location: start, length: 1))
                let updated = paragraphRange(at: start)
                storage.removeAttribute(.obfTaskState, range: updated)
                storage.removeAttribute(.obfTaskCreated, range: updated)
                textView.setSelectedRange(NSRange(location: start, length: 0))
                applyStyles(in: updated)
                syncTypingAttributes()
                return true
            }
            textView.typingAttributes = styleAttributes(for: nil)
            textView.insertText("\n", replacementRange: selection)
            let tail = paragraphRange(at: selection.location + 1)
            storage.removeAttribute(.obfTaskState, range: tail)
            storage.removeAttribute(.obfTaskCreated, range: tail)
            textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            textView.typingAttributes = styleAttributes(for: nil)
            return true
        }

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
        updateCurrentHeading()
    }

    /// Marks the headings the caret is under — the nearest H1 above it and,
    /// below that H1, the nearest H2 — for the "Структура" tab. Right under
    /// an H1 (before its first H2) only the H1 is marked.
    private func updateCurrentHeading() {
        guard let textView else { return }
        let caret = textView.selectedRange().location
        let above = appState.outline.filter { $0.range.location <= caret }
        let h1 = above.last { $0.level == 1 }
        let h2 = above.last { $0.level == 2 && $0.range.location > (h1?.range.location ?? -1) }
        let ids = Set([h1?.id, h2?.id].compactMap { $0 })
        if appState.currentOutlineIDs != ids {
            appState.currentOutlineIDs = ids
        }
    }

    // MARK: - Find

    func updateFindMatches() {
        updateFindMatches(resetIndex: true, scroll: true)
    }

    private func updateFindMatches(resetIndex: Bool, scroll: Bool) {
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
            if scroll {
                selectCurrentMatch()
            } else {
                applyMatchHighlight()
            }
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

    /// Highlights the current match and scrolls it into view. Used only for
    /// explicit navigation (query change, next/prev, opening the bar) — never
    /// from background refreshes, so the user's own scrolling is never
    /// overridden.
    private func selectCurrentMatch() {
        applyMatchHighlight()
        guard let textView, let range = highlightedMatch else { return }
        textView.scrollRangeToVisible(range)
    }

    /// The match is highlighted with a background attribute in the text
    /// storage: it keeps selectionNS regardless of focus (AppKit would
    /// otherwise draw the selection with system colors), it shifts with
    /// edits like any attribute, and the text selection itself is left
    /// alone so no "stuck" selection can survive closing the find bar.
    private func applyMatchHighlight() {
        guard appState.findVisible else { return }
        guard let storage = textView?.textStorage,
              appState.currentMatchIndex < appState.matches.count else { return }
        let range = appState.matches[appState.currentMatchIndex]
        guard NSMaxRange(range) <= storage.length else { return }
        // Already in place: touching the attribute again would only fire
        // another round of storage notifications.
        guard highlightedMatch != range else { return }
        clearMatchHighlight()
        storage.addAttribute(.backgroundColor, value: OBFTheme.selectionNS, range: range)
        highlightedMatch = range
    }

    /// Callers must wrap edits in begin/end editing (or tolerate the
    /// resulting notifications): removing the attribute fires a storage
    /// notification of its own, and highlightedMatch is nil by then.
    /// The attribute is cleared across the WHOLE storage, not just the
    /// tracked range: text edits shift attributes along with the
    /// characters, so the tracked range can be stale and a partial removal
    /// would leave highlight residue behind. backgroundColor is used for
    /// the find highlight only, so a full-range clear is safe.
    private func clearMatchHighlight() {
        guard highlightedMatch != nil, let storage = textView?.textStorage else { return }
        if storage.length > 0 {
            storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
        }
        highlightedMatch = nil
    }

    func clearFindHighlight() {
        guard highlightedMatch != nil, let storage = textView?.textStorage else { return }
        storage.beginEditing()
        clearMatchHighlight()
        storage.endEditing()
    }

    /// Collapses the text selection to a caret: opening and closing the
    /// find bar must leave no selection behind anywhere in the document.
    func clearSelection() {
        guard let textView else { return }
        let selection = textView.selectedRange()
        guard selection.length > 0 else { return }
        textView.setSelectedRange(NSRange(location: selection.location, length: 0))
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Test hook: the live text view, for --replay modes that drive the real
    /// app window.
    var debugTextView: OBFTextView? { textView }
    var debugAppState: AppState { appState }
    /// Tests: rebuild the outline now (normally debounced after edits).
    func debugRebuildOutline() {
        rebuildOutline()
    }

    /// Tests: restyle the whole document (loadDocument does this).
    func debugApplyStyles() {
        guard let storage = textView?.textStorage, storage.length > 0 else { return }
        applyStyles(in: NSRange(location: 0, length: storage.length))
    }

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
