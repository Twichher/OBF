import AppKit

/// Headless reproduction of user keystroke sequences. Run the app binary with
/// `--selftest`; prints the state of typing attributes and paragraph markers
/// after every step so style leaks can be traced to the exact operation.
enum SelfTest {

    static func run() -> Int32 {
        var failures = 0

        print("== A: heading, Enter, type, Enter, Backspace, type ==")
        if !scenarioA() { failures += 1 }

        print("== B: user repro — heading, Enter, Enter, Backspace, type (empty line) ==")
        if !scenarioB() { failures += 1 }

        print("== C: Cmd+1 on empty line under a heading ==")
        if !scenarioC() { failures += 1 }

        print("== D: find cycles through matches with Enter (wraps around) ==")
        if !scenarioD() { failures += 1 }

        print("== E: highlight stays off after closing find and refreshing ==")
        if !scenarioE() { failures += 1 }

        print("== F: long line wraps within the text view width ==")
        if !scenarioF() { failures += 1 }

        print("== G: typing over a selection (crash repro, issue #4-style) ==")
        if !scenarioG() { failures += 1 }

        print("== H: find clears selection; highlight survives edits/zoom; close clears all ==")
        if !scenarioH() { failures += 1 }

        print("== I: two-finger swipe recognizer (left=next, right=prev, once per gesture) ==")
        if !scenarioI() { failures += 1 }

        print("== J: Cmd+3 creates a task, typing follows, Enter ends it, markdown round-trip ==")
        if !scenarioJ() { failures += 1 }

        print("== K: Cmd+4 toggles done (dimmed text, - [x]) ==")
        if !scenarioK() { failures += 1 }

        print("== L: Backspace right after the checkbox un-tasks the line, keeps text ==")
        if !scenarioL() { failures += 1 }

        print("== M: markdown parse/serialize round-trip with tasks ==")
        if !scenarioM() { failures += 1 }

        print("== N: task text wraps with hanging indent aligned after the checkbox ==")
        if !scenarioN() { failures += 1 }

        print("== O: sidebar task list — dates, order, location paths, round-trip ==")
        if !scenarioO() { failures += 1 }

        print("== P: sidebar task uids survive edits above and done-toggle ==")
        if !scenarioP() { failures += 1 }

        print("== Q: expanded task text height is capped (scrolls past 8 lines) ==")
        if !scenarioQ() { failures += 1 }

        print("== R: Enter from a task clears the typing mark; only the new task is marked ==")
        if !scenarioR() { failures += 1 }

        print("== S: expanded task text eats scroll events at its edges ==")
        if !scenarioS() { failures += 1 }

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    private static func makeStack() -> (AppState, OBFTextView, Coordinator, NSTextStorage) {
        // Tests write to a temp file: the debounced auto-save must never
        // touch the real document.
        let appState = AppState(store: DocumentStore(fileURL: URL(fileURLWithPath: "/tmp/obf_selftest_document.md")))
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        coordinator.loadDocument()
        // Work on a fresh, deterministic document instead of the real file.
        storage.setAttributedString(NSAttributedString())
        return (appState, textView, coordinator, storage)
    }

    private static func type(_ textView: OBFTextView, _ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Lets deferred main-queue work (typing-attribute sync, restyling)
    /// run, the way it would between real keystrokes.
    private static func pump() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    /// A paragraph's level is the marker on its first character; the trailing
    /// newline never carries it. Empty paragraphs report nil.
    private static func paragraphMarkers(_ storage: NSTextStorage) -> [String] {
        let ns = storage.string as NSString
        var levels: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let last = ns.character(at: NSMaxRange(enclosing) - 1)
            let contentLength = (last == 0x0A || last == 0x0D) ? enclosing.length - 1 : enclosing.length
            guard contentLength > 0 else { levels.append("empty"); return }
            if let task = storage.attribute(.obfTaskState, at: enclosing.location, effectiveRange: nil) as? Int {
                levels.append(task == 2 ? "done" : "task")
                return
            }
            levels.append(storage.attribute(.obfHeadingLevel, at: enclosing.location, effectiveRange: nil) as? Int == 1 ? "H1"
                        : storage.attribute(.obfHeadingLevel, at: enclosing.location, effectiveRange: nil) as? Int == 2 ? "H2"
                        : "body")
        }
        return levels
    }

    private static func dump(_ label: String, _ textView: OBFTextView, _ storage: NSTextStorage) {
        let marker = textView.typingAttributes[.obfHeadingLevel] as? Int
        let font = textView.typingAttributes[.font] as? NSFont
        let sel = textView.selectedRange()
        print("  [\(label)] sel=(\(sel.location),\(sel.length)) typing marker=\(marker.map(String.init) ?? "nil") font=\(font.map { "\($0.pointSize)pt" } ?? "nil")")
        print("    storage: \(storage.string.debugDescription)")
        print("    paragraphs: \(paragraphMarkers(storage))")
    }

    private static func typedCharIsBody(_ textView: OBFTextView, _ storage: NSTextStorage, appState: AppState) -> Bool {
        let index = textView.selectedRange().location - 1
        guard index >= 0 else { return false }
        let marker = storage.attribute(.obfHeadingLevel, at: index, effectiveRange: nil) as? Int
        let size = (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize
        return marker == nil && size == appState.bodyFont.pointSize
    }

    /// Heading with text typed below it: Enter exits to body, further edits
    /// must not bring the heading style back.
    private static func scenarioA() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        type(textView, "обычный текст")
        textView.insertNewline(nil)
        textView.deleteBackward(nil)
        dump("after Backspace", textView, storage)
        pump()

        let markerBefore = paragraphMarkers(storage)
        let typingClean = textView.typingAttributes[.obfHeadingLevel] == nil
        type(textView, "X")
        dump("after typing X", textView, storage)

        let ok = typingClean && typedCharIsBody(textView, storage, appState: appState) && paragraphMarkers(storage) == markerBefore
        print("    -> OK: \(ok)")
        return ok
    }

    /// Exact user repro: heading, Enter (empty line below), Enter again,
    /// Backspace — caret ends on the empty line under the heading; typing
    /// there must stay body text.
    private static func scenarioB() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        textView.insertNewline(nil)
        textView.deleteBackward(nil)
        dump("after Backspace", textView, storage)
        pump()

        let markerBefore = paragraphMarkers(storage)
        let typingClean = textView.typingAttributes[.obfHeadingLevel] == nil
        type(textView, "X")
        dump("after typing X", textView, storage)

        let ok = typingClean
            && typedCharIsBody(textView, storage, appState: appState)
            && paragraphMarkers(storage) == ["H1", "body"]
            && markerBefore == ["H1"]
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+1 on an empty line directly under a heading must turn THAT line
    /// into a heading (via typing attributes) and must not touch the heading
    /// above.
    private static func scenarioC() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        // Caret is now on the empty line under the heading.
        coordinator.setHeadingLevel(1)
        dump("after Cmd+1 on empty line", textView, storage)
        type(textView, "X")
        dump("after typing X", textView, storage)

        let markers = paragraphMarkers(storage)
        let ok = markers == ["H1", "H1"]
        print("    -> OK: \(ok) (markers: \(markers))")
        return ok
    }

    /// findNext/findPrev must cycle through matches endlessly: with 3 matches
    /// four findNext calls visit 1, 2, 3, then wrap back to 1.
    private static func scenarioD() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()

        type(textView, "X один\nX два\nX три")
        appState.findQuery = "X"
        coordinator.updateFindMatches()

        var indexes: [Int] = [appState.currentMatchIndex]
        for _ in 0..<4 {
            coordinator.findNext()
            indexes.append(appState.currentMatchIndex)
        }
        coordinator.findPrev()
        indexes.append(appState.currentMatchIndex)

        let ok = appState.matches.count == 3 && indexes == [0, 1, 2, 0, 1, 0]
        print("    matches=\(appState.matches.count) indexes=\(indexes) -> OK: \(ok)")
        return ok
    }

    /// Closing the find bar removes the highlight for good: neither a later
    /// updateFindMatches (the debounced refresh after edits) nor typing may
    /// bring the highlight back while the bar is closed.
    private static func scenarioE() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "X один\nX два\nX три")
        appState.findQuery = "X"
        appState.findVisible = true
        coordinator.updateFindMatches()
        let highlightedWhileOpen = hasBackgroundAttribute(storage)

        appState.findVisible = false
        coordinator.clearFindHighlight()
        let clearedAfterClose = !hasBackgroundAttribute(storage)

        // Simulates the 0.5s refresh that follows any edit: previously it
        // re-added the highlight even though the find bar was closed.
        coordinator.updateFindMatches()
        type(textView, "Y")
        let staysClear = !hasBackgroundAttribute(storage)

        print("    open=\(highlightedWhileOpen) closed=\(clearedAfterClose) staysClear=\(staysClear)")
        let ok = highlightedWhileOpen && clearedAfterClose && staysClear
        print("    -> OK: \(ok)")
        return ok
    }

    private static func hasBackgroundAttribute(_ storage: NSTextStorage) -> Bool {
        guard storage.length > 0 else { return false }
        var found = false
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// A long line must wrap at the text container width — the used layout
    /// rect must never be wider than the container.
    private static func scenarioF() -> Bool {
        let (_, textView, _, _) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        let longWord = String(repeating: "слово", count: 40)
        let longLine = (0..<60).map { _ in longWord }.joined(separator: " ")
        type(textView, longLine)
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)

        let used = layoutManager.usedRect(for: container)
        print("    frame=\(textView.frame.width) container=\(container.containerSize.width) used=\(used.width)")
        let ok = container.containerSize.width > 0 && used.width <= container.containerSize.width + 0.5
        print("    -> OK: \(ok)")
        return ok
    }

    /// Crash repro: the user selects a stretch of text and starts typing
    /// without deleting first. In the app this died inside
    /// -[NSTextStorage ensureAttributesAreFixedInRange:] during drawRect, so
    /// besides replacing the characters we force a full layout and display
    /// pass here. Also exercised with an active find highlight over the
    /// selection — the highlight is a plain background attribute and the most
    /// invasive storage mutation we do outside of plain typing.
    private static func scenarioG() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        type(textView, "Первая строка\nВторая строка\nТретья строка")
        let full = NSRange(location: 0, length: storage.length)

        // Plain: select across paragraphs, type over it.
        textView.setSelectedRange(full)
        type(textView, "замена")
        var ok = storage.string == "замена"

        // With a live find highlight sitting on the replaced range.
        type(textView, "\nальфа бета альфа")
        appState.findQuery = "альфа"
        appState.findVisible = true
        coordinator.updateFindMatches()
        let highlighted = hasBackgroundAttribute(storage)
        textView.setSelectedRange(NSRange(location: 6, length: storage.length - 6))
        type(textView, "гамма")
        let survived = storage.string == "замена\ngамма" || storage.string.hasPrefix("замена")
        appState.findVisible = false
        coordinator.clearFindHighlight()

        // Force the drawing path that crashed: full layout + display.
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)
        textView.display()

        print("    replaced ok=\(ok) highlighted=\(highlighted) after=\(storage.string.debugDescription)")
        ok = ok && highlighted && survived
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+F must drop the pre-existing selection; the match highlight must
    /// survive edits, whole-document restyles (zoom) and background
    /// refreshes; closing find must remove both the highlight and any
    /// selection left in the text.
    private static func scenarioH() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()
        appState.editor = coordinator

        type(textView, "альфа бета\nальфа гамма\nальфа дельта")

        // A selection made before searching must be cleared by Cmd+F.
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        appState.findQuery = "альфа"
        appState.showFindBar()
        let selectionClearedOnOpen = textView.selectedRange().length == 0
        let highlightedOnOpen = hasBackgroundAttribute(storage)

        // Typing restyles the paragraph on the next run-loop turn; the
        // highlight must be re-applied there, not 0.5 s later.
        type(textView, "!")
        pump()
        let highlightedAfterEdit = hasBackgroundAttribute(storage)

        // Zoom restyles the whole document without any character edit.
        // bodyPointSize persists to UserDefaults, so restore it afterwards —
        // otherwise every test run would leak a zoom step.
        let savedPointSize = appState.bodyPointSize
        coordinator.zoomIn()
        let highlightedAfterZoom = hasBackgroundAttribute(storage)
        appState.bodyPointSize = savedPointSize

        // Closing find removes the highlight and any selection.
        textView.setSelectedRange(NSRange(location: 2, length: 3))
        appState.closeFind()
        let clearedOnClose = !hasBackgroundAttribute(storage) && textView.selectedRange().length == 0

        print("    open: selCleared=\(selectionClearedOnOpen) highlighted=\(highlightedOnOpen)")
        print("    afterEdit=\(highlightedAfterEdit) afterZoom=\(highlightedAfterZoom) clearedOnClose=\(clearedOnClose)")
        let ok = selectionClearedOnOpen && highlightedOnOpen && highlightedAfterEdit && highlightedAfterZoom && clearedOnClose
        print("    -> OK: \(ok)")
        return ok
    }

    /// Reproduces "lines overflow the working area until the first scroll":
    /// measures the editor geometry right after launch (no user actions) and
    /// again after a programmatic scroll, printing text view / clip view /
    /// text container widths and the rightmost laid-out line fragment.
    /// Also captures window snapshots for visual inspection of the sidebar:
    /// initial state, the tab list under a simulated hover over the tab
    /// title, and an empty tab. Launched with --uitest-open; exits the
    /// process when done.
    static func measureOpen(appState: AppState) {
        func measure(_ label: String) {
            guard let coordinator = appState.editor as? Coordinator,
                  let textView = coordinator.debugTextView,
                  let lm = textView.layoutManager,
                  let tc = textView.textContainer,
                  let sv = textView.enclosingScrollView else {
                print("OPEN-MEASURE \(label): missing view stack")
                return
            }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            var maxRight: CGFloat = 0
            if lm.numberOfGlyphs > 0 {
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, _, _ in
                    maxRight = max(maxRight, rect.maxX)
                }
            }
            let overflow = maxRight > tc.containerSize.width + 0.5
                || textView.frame.width > sv.contentSize.width + 0.5
            print("OPEN-MEASURE \(label): tvW=\(textView.frame.width) clipW=\(sv.contentSize.width) contW=\(tc.containerSize.width) usedW=\(used.width) maxRight=\(maxRight) overflow=\(overflow)")
        }
        /// Renders the window's own view hierarchy — no screen-recording
        /// permission needed, unlike CGWindowListCreateImage.
        func snap(_ window: NSWindow, _ name: String) {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("OPEN-MEASURE snap \(name): FAILED")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_open_\(name).png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            measure("t=0.8")
            guard let coordinator = appState.editor as? Coordinator,
                  let textView = coordinator.debugTextView,
                  let sv = textView.enclosingScrollView,
                  let window = textView.window,
                  let content = window.contentView else { exit(1) }
            snap(window, "1_initial")

            /// Posts a synthetic trackpad-style scroll event (with gesture
            /// phase) at a window point — lets the swipe pipeline be tested
            /// end to end without real touch input. Phase values mirror
            /// NSEvent.Phase raw values: 1 = began, 2 = changed, 4 = ended.
            func postScroll(at point: NSPoint, phase: Int64, dx: Int32, dy: Int32) {
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let cg = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                let screenRect = window.convertToScreen(CGRect(origin: point, size: .zero))
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                cg.location = CGPoint(x: screenRect.origin.x, y: mainHeight - screenRect.origin.y)
                if let nsEvent = NSEvent(cgEvent: cg) {
                    NSApplication.shared.postEvent(nsEvent, atStart: false)
                }
            }
            func swipe(at point: NSPoint, dx: Int32, dy: Int32, steps: Int) {
                postScroll(at: point, phase: 1, dx: 0, dy: 0)
                for _ in 0..<steps {
                    postScroll(at: point, phase: 2, dx: dx, dy: dy)
                }
                postScroll(at: point, phase: 4, dx: 0, dy: 0)
            }

            let sidebarPoint = NSPoint(x: 924 + 130, y: 400)
            let editorPoint = NSPoint(x: 400, y: 400)
            SelfTest.loggingScrollEvents = true
            appState.sidebarTab = .structure
            swipe(at: sidebarPoint, dx: -15, dy: 0, steps: 6)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // Assert direction relative to the deltas the monitor
                // actually saw, so CG→NS sign mapping cannot skew the test.
                let sawNegativeX = SelfTest.debugScrollLog.contains { $0.contains("dx=-") }
                let expected: SidebarTab = sawNegativeX ? .tasks : .structure
                let leftOK = appState.sidebarTab == expected
                print("OPEN-MEASURE swipe-over-sidebar: tab=\(appState.sidebarTab.title) expected=\(expected.title) ok=\(leftOK)")
                print("OPEN-MEASURE scroll-log: \(SelfTest.debugScrollLog)")
                SelfTest.debugScrollLog = []
                // Vertical gesture and horizontal gesture over the editor
                // must NOT switch tabs.
                swipe(at: sidebarPoint, dx: 0, dy: -15, steps: 6)
                swipe(at: editorPoint, dx: -15, dy: 0, steps: 6)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let ignoredOK = appState.sidebarTab == .tasks
                    print("OPEN-MEASURE vertical+editor swipes ignored: tab=\(appState.sidebarTab.title) ok=\(ignoredOK)")
                    SelfTest.loggingScrollEvents = false

                    // Simulate hovering the sidebar tab title: warp the
                    // cursor onto it and post mouse-moved events so
                    // SwiftUI's onHover fires. The point comes from the
                    // fixed layout (see OBFTheme): the sidebar's tab title
                    // is centered in the bottom bar.
                    let hoverPoint = NSPoint(x: 924 + 130, y: 40)
                    let restore = CGEvent(source: nil)?.location
                    let screenRect = window.convertToScreen(CGRect(origin: hoverPoint, size: .zero))
                    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                    CGWarpMouseCursorPosition(CGPoint(x: screenRect.origin.x, y: mainHeight - screenRect.origin.y))
                    if let moved = NSEvent.mouseEvent(
                        with: .mouseMoved,
                        location: hoverPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 0,
                        pressure: 0
                    ) {
                        NSApplication.shared.postEvent(moved, atStart: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NSApplication.shared.postEvent(moved, atStart: false)
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        snap(window, "2_hover_tablist")
                        appState.sidebarTab = .tasks
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            snap(window, "3_empty_tab")
                            if let restore {
                                CGWarpMouseCursorPosition(restore)
                            }
                            // Visual check of task rendering and the
                            // "Задания" tab: swap in a demo document, wait
                            // for the debounced refresh that rebuilds the
                            // sidebar lists, snap, then restore the original
                            // and save it back immediately.
                            guard let storage = textView.textStorage else { exit(1) }
                            let original = storage.string
                            storage.setAttributedString(coordinator.render(markdown: """
                                # Проект OneBigFile
                                ## Раздел первый
                                Обычный текст перед заданием
                                - [ ] <!-- 2026-09-20 --> Купить молоко и хлеб
                                - [x] <!-- 2026-09-19 --> Сдать лабораторную работу
                                - [ ] <!-- 2026-09-21 --> Очень длинное задание, которое точно не влезет в одну строку редактора и должно перенестись на следующую строку с отступом
                                Обычный текст после задания
                                """))
                            // Mid-animation snapshot (~0.2 s after the
                            // debounced refresh starts the insertion
                            // transition), then the settled state.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                snap(window, "4a_tasks_animating")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                snap(window, "4_tasks")
                                // Typing in a task: its card switches to
                                // the wiggling "Печатаем задание" state.
                                if let firstTask = appState.tasks.first {
                                    textView.setSelectedRange(NSRange(location: firstTask.range.location + 1, length: 0))
                                    textView.insertText("…", replacementRange: textView.selectedRange())
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    snap(window, "5_typing_task")
                                    // Bug repro: Enter from inside the
                                    // task, Cmd+3 on the new line, type —
                                    // only the NEW card may wiggle.
                                    if let firstTask = appState.tasks.first {
                                        textView.setSelectedRange(NSRange(location: NSMaxRange(firstTask.range) - 1, length: 0))
                                    }
                                    textView.insertNewline(nil)
                                    coordinator.toggleTask()
                                    textView.insertText("абв", replacementRange: textView.selectedRange())
                                    // Let the debounced refresh create
                                    // the new card, then keep typing so
                                    // the snapshot catches it wiggling
                                    // while the old card stays still.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        textView.insertText("г", replacementRange: textView.selectedRange())
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            snap(window, "6_enter_cmd3_typing")
                                            storage.setAttributedString(coordinator.render(markdown: original))
                                            // The demo refresh saved the
                                            // demo to disk; write the
                                            // original back right now.
                                            coordinator.saveNow()
                                            sv.contentView.scroll(to: NSPoint(x: 0, y: 120))
                                            sv.reflectScrolledClipView(sv.contentView)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                measure("after-scroll")
                                                _ = content
                                                exit(0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Two-finger horizontal swipes switch sidebar tabs: fingers left →
    /// next, right → prev, at most one switch per gesture; mostly-vertical
    /// scrolling and short drags never trigger.
    private static func scenarioI() -> Bool {
        var recognizer = HorizontalSwipeRecognizer()

        func gesture(_ dx: CGFloat, _ dy: CGFloat, steps: Int) -> [SidebarTabMove] {
            var moves: [SidebarTabMove] = []
            if let move = recognizer.handle(phase: .began, deltaX: 0, deltaY: 0) { moves.append(move) }
            for _ in 0..<steps {
                if let move = recognizer.handle(phase: .changed, deltaX: dx, deltaY: dy) { moves.append(move) }
            }
            if let move = recognizer.handle(phase: .ended, deltaX: 0, deltaY: 0) { moves.append(move) }
            return moves
        }

        let left = gesture(-12, 2, steps: 8)       // -96 horizontal: next
        let right = gesture(12, -2, steps: 8)      // +96 horizontal: prev
        let vertical = gesture(2, -12, steps: 8)   // vertical-dominant: none
        let short = gesture(-5, 0, steps: 5)       // -25 < threshold: none

        print("    left=\(left) right=\(right) vertical=\(vertical) short=\(short)")
        let ok = left == [.next] && right == [.prev] && vertical.isEmpty && short.isEmpty
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+3 on an empty line inserts the checkbox immediately; typing goes
    /// after it; Enter ends the task and continues in plain body text.
    /// Serialization stores the paragraph as a markdown task.
    private static func scenarioJ() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        coordinator.toggleTask()
        let checkboxThere = storage.string == "\u{FFFC}"
            && storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 1
            && storage.attribute(.attachment, at: 0, effectiveRange: nil) != nil

        type(textView, "текст задания")
        textView.insertNewline(nil)
        type(textView, "обычный текст")
        pump()

        let markers = paragraphMarkers(storage)
        let serialized = coordinator.serialize(storage: storage)
        // Tasks created via Cmd+3 carry today's date as a hidden comment.
        let expected = "- [ ] <!-- \(Self.todayString()) --> текст задания\nобычный текст"
        print("    checkbox=\(checkboxThere) markers=\(markers) serialized=\(serialized.debugDescription)")
        let ok = checkboxThere && markers == ["task", "body"] && serialized == expected
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+4 marks the task under the caret done (checkmark, dimmed text,
    /// "- [x]" on save) and toggles back on a second press.
    private static func scenarioK() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "сделать дело")
        coordinator.toggleTask()
        coordinator.toggleTaskDone()
        pump()

        let markedDone = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 2
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        let dimmed = color != nil && color!.alphaComponent < 0.6
        let serialized = coordinator.serialize(storage: storage)

        coordinator.toggleTaskDone()
        pump()
        let backToTodo = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 1

        print("    done=\(markedDone) dimmed=\(dimmed) serialized=\(serialized.debugDescription) backToTodo=\(backToTodo)")
        let ok = markedDone && dimmed && serialized == "- [x] <!-- \(Self.todayString()) --> сделать дело" && backToTodo
        print("    -> OK: \(ok)")
        return ok
    }

    /// Backspace with the caret immediately after the checkbox removes the
    /// task formatting but keeps the text.
    private static func scenarioL() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "текст задания")
        coordinator.toggleTask()
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.deleteBackward(nil)
        pump()

        let untasked = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) == nil
        let textKept = storage.string == "текст задания"
        print("    untasked=\(untasked) text=\(storage.string.debugDescription)")
        let ok = untasked && textKept
        print("    -> OK: \(ok)")
        return ok
    }

    /// Markdown round-trip: headings, tasks (todo and done), plain bullets
    /// and body text parse and serialize back to the identical string.
    private static func scenarioM() -> Bool {
        let (_, _, coordinator, storage) = makeStack()

        let markdown = "# Заголовок\n- [ ] сделать раз\n- [x] сделано два\n- просто пункт\nобычный текст"
        storage.setAttributedString(coordinator.render(markdown: markdown))
        let serialized = coordinator.serialize(storage: storage)
        print("    roundtrip=\(serialized == markdown)")
        if serialized != markdown {
            print("    got: \(serialized.debugDescription)")
        }
        let ok = serialized == markdown
        print("    -> OK: \(ok)")
        return ok
    }

    /// A task's wrapped lines align with the text after the checkbox (the
    /// hanging indent equals the checkbox width including its gap).
    private static func scenarioN() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        coordinator.toggleTask()
        let longLine = (0..<60).map { _ in "слово" }.joined(separator: " ")
        type(textView, longLine)
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)

        var lineStarts: [CGFloat] = []
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { rect, _, _, glyphRange, _ in
            let location = layoutManager.location(forGlyphAt: glyphRange.location)
            lineStarts.append(rect.minX + location.x)
        }
        let indent = ceil(appState.bodyFont.pointSize * 0.85) + 6
        let padding = container.lineFragmentPadding
        print("    lineStarts=\(lineStarts) indent=\(indent) padding=\(padding)")
        let ok = lineStarts.count > 1
            && abs(lineStarts[0] - padding) < 0.5
            && lineStarts.dropFirst().allSatisfy { abs($0 - padding - indent) < 0.5 }
        print("    -> OK: \(ok)")
        return ok
    }

    /// The "Задания" sidebar tab: dated tasks round-trip through markdown
    /// with their hidden comment, the list is grouped active-then-done with
    /// the newest on top of each group, and a task knows the headings above
    /// it. A task created via Cmd+3 gets today's date.
    private static func scenarioO() -> Bool {
        let (appState, _, coordinator, storage) = makeStack()

        let markdown = """
        # Проект
        ## Первая часть
        - [ ] <!-- 2026-09-20 --> старое задание
        - [ ] <!-- 2026-09-21 --> новое задание
        - [x] <!-- 2026-09-19 --> выполненное задание
        ## Вторая часть
        - [ ] задание без даты
        """
        storage.setAttributedString(coordinator.render(markdown: markdown))
        // Save + reload: rebuilds the sidebar data from a fresh render.
        coordinator.saveNow()
        coordinator.loadDocument()

        let roundTrip = coordinator.serialize(storage: storage) == markdown
        let tasks = appState.tasks
        for task in tasks {
            print("    task text=\(task.text.debugDescription) done=\(task.done) created=\(task.created ?? "nil") h1=\(task.h1 ?? "nil") h2=\(task.h2 ?? "nil")")
        }

        let countOk = tasks.count == 4
        // Active newest-first, then done newest-first; dateless tasks sink
        // to the bottom of their group.
        let orderOk = countOk
            && tasks.map(\.text) == ["новое задание", "старое задание", "задание без даты", "выполненное задание"]
            && tasks[3].done
        let datesOk = countOk
            && tasks[0].created == "2026-09-21"
            && tasks[1].created == "2026-09-20"
            && tasks[2].created == nil
            && tasks[3].created == "2026-09-19"
        let pathsOk = countOk
            && tasks[0].h1 == "Проект" && tasks[0].h2 == "Первая часть"
            && tasks[2].h1 == "Проект" && tasks[2].h2 == "Вторая часть"

        // A fresh Cmd+3 task gets today's date, serialized as a comment.
        let (_, textView2, coordinator2, storage2) = makeStack()
        type(textView2, "свежее задание")
        coordinator2.toggleTask()
        pump()
        let created = storage2.attribute(.obfTaskCreated, at: 0, effectiveRange: nil) as? String
        let serialized2 = coordinator2.serialize(storage: storage2)
        let todayOk = created == Self.todayString()
            && serialized2 == "- [ ] <!-- \(Self.todayString()) --> свежее задание"

        print("    roundTrip=\(roundTrip) order=\(orderOk) dates=\(datesOk) paths=\(pathsOk) today=\(todayOk)")
        let ok = roundTrip && orderOk && datesOk && pathsOk && todayOk
        print("    -> OK: \(ok)")
        return ok
    }

    /// Sidebar card identity (uid) survives edits above the task and a
    /// done-toggle: only position/state change, so the sidebar animates the
    /// existing card instead of re-creating it.
    private static func scenarioP() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        storage.setAttributedString(coordinator.render(markdown: """
        # Проект
        текст
        - [ ] <!-- 2026-09-20 --> первое
        - [ ] <!-- 2026-09-21 --> второе
        """))
        coordinator.saveNow()
        coordinator.loadDocument()

        let before = appState.tasks
        let countOk = before.count == 2

        // An edit in the body line above the tasks shifts their ranges by
        // 3 without touching headings or task content; identities must not
        // change, otherwise the sidebar would re-animate both cards.
        let bodyLine = "# Проект".count + 1
        textView.setSelectedRange(NSRange(location: bodyLine, length: 0))
        type(textView, "xxx")
        pump()
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterEdit = appState.tasks
        let uidsStable = countOk && afterEdit.map(\.uid) == before.map(\.uid)
        let rangesShifted = countOk && afterEdit.count == 2
            && zip(before, afterEdit).allSatisfy {
                $1.range.location == $0.range.location + 3
            }

        // Typing inside a task marks its card as "being typed" and the
        // card keeps its identity across the rebuild (no re-creation).
        let typedTask = afterEdit[0]
        textView.setSelectedRange(NSRange(location: typedTask.range.location + 1, length: 0))
        type(textView, "yy")
        pump()
        let hintOk = appState.editingTaskLocation == typedTask.range.location
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterTyping = appState.tasks
        let typedUidStable = hintOk
            && afterTyping.first?.uid == typedTask.uid
            && afterTyping.first?.text == "yyвторое"

        // Cmd+4 flips done: the card keeps its uid and moves to the done
        // group at the end of the list.
        let toggledUID = afterTyping.first?.uid
        if let first = afterTyping.first {
            textView.setSelectedRange(NSRange(location: first.range.location, length: 0))
        }
        coordinator.toggleTaskDone()
        pump()
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterToggle = appState.tasks
        let moved = toggledUID != nil
            && afterToggle.count == 2
            && afterToggle.last?.uid == toggledUID
            && afterToggle.last?.done == true

        print("    count=\(countOk) uidsStable=\(uidsStable) shifted=\(rangesShifted) hint=\(hintOk) typedUid=\(typedUidStable) moved=\(moved)")
        let ok = countOk && uidsStable && rangesShifted && typedUidStable && moved
        print("    -> OK: \(ok)")
        return ok
    }

    /// Expanded task text: never shorter than the collapsed two-line box,
    /// grows with the text, and stops at the eight-line cap — longer texts
    /// scroll inside the box.
    private static func scenarioQ() -> Bool {
        let words = "строка текста задания "
        let short = TaskCardView.expandedHeight(for: "короткое")
        let mid = TaskCardView.expandedHeight(for: String(repeating: words, count: 4))
        let long = TaskCardView.expandedHeight(for: String(repeating: words, count: 40))
        let longer = TaskCardView.expandedHeight(for: String(repeating: words, count: 80))

        let ok = mid > short && long > mid && longer == long
        print("    short=\(short) mid=\(mid) long=\(long) longer=\(longer)")
        print("    -> OK: \(ok)")
        return ok
    }

    /// Enter from inside a task moves the caret to a new plain line, so
    /// the OLD task's card must leave the typing state; after Cmd+3 on the
    /// new line only the NEW task is marked as being typed.
    private static func scenarioR() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()

        coordinator.toggleTask()
        type(textView, "первое")
        pump()
        let typingA = appState.editingTaskLocation == 0

        textView.insertNewline(nil)
        pump()
        let clearedAfterEnter = appState.editingTaskLocation == nil

        coordinator.toggleTask()
        pump()
        let newLocation = appState.editingTaskLocation
        let markedNew = newLocation != nil && newLocation != 0

        type(textView, "второе")
        pump()
        let staysNew = appState.editingTaskLocation == newLocation

        print("    typingA=\(typingA) clearedAfterEnter=\(clearedAfterEnter) markedNew=\(markedNew) staysNew=\(staysNew)")
        let ok = typingA && clearedAfterEnter && markedNew && staysNew
        print("    -> OK: \(ok)")
        return ok
    }

    /// The expanded task text box (TrappedScrollView) scrolls its own
    /// content when it can and consumes the event at its edges — the event
    /// is never forwarded up the responder chain, so the sidebar's scroll
    /// view cannot start scrolling while the pointer is inside the box.
    private static func scenarioS() -> Bool {
        final class ScrollProbe: NSResponder {
            var received = 0
            override func scrollWheel(with event: NSEvent) { received += 1 }
        }

        let scrollView = TrappedScrollView(frame: NSRect(x: 0, y: 0, width: 168, height: 128))
        let textView = FlippedTextView(frame: NSRect(x: 0, y: 0, width: 168, height: 500))
        textView.string = (1...40).map(String.init).joined(separator: "\n")
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        let probe = ScrollProbe()
        scrollView.nextResponder = probe

        func wheel(_ dy: Int32) -> NSEvent? {
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let cg = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0),
                  let event = NSEvent(cgEvent: cg) else { return nil }
            return event
        }
        guard let positive = wheel(10), let negative = wheel(-10) else {
            print("    -> OK: false (cannot synthesize scroll events)")
            return false
        }
        // Which sign scrolls toward the bottom depends on the system's
        // natural-scrolling setting; read it from the event itself.
        let towardBottom = positive.isDirectionInvertedFromDevice ? positive : negative
        let towardTop = positive.isDirectionInvertedFromDevice ? negative : positive

        // At the top, a toward-top event is eaten: no movement, no forward.
        scrollView.scrollWheel(with: towardTop)
        let stayedAtTop = scrollView.contentView.bounds.origin.y == 0
        let notForwardedAtTop = probe.received == 0

        // Toward-bottom events scroll the content...
        for _ in 0..<100 { scrollView.scrollWheel(with: towardBottom) }
        let bottomOffset = scrollView.contentView.bounds.origin.y
        let scrolledDown = bottomOffset > 0
        let notForwardedWhileScrolling = probe.received == 0

        // ...and at the bottom the event is eaten again.
        scrollView.scrollWheel(with: towardBottom)
        let stayedAtBottom = scrollView.contentView.bounds.origin.y == bottomOffset
        let notForwardedAtBottom = probe.received == 0

        print("    stayedAtTop=\(stayedAtTop) scrolledDown=\(scrolledDown) bottom=\(bottomOffset) stayedAtBottom=\(stayedAtBottom) forwarded=\(probe.received)")
        let ok = stayedAtTop && scrolledDown && stayedAtBottom
            && notForwardedAtTop && notForwardedWhileScrolling && notForwardedAtBottom
        print("    -> OK: \(ok)")
        return ok
    }

    /// Drives the REAL app window (SwiftUI stack included) through the
    /// ghost-line scenario and saves screen captures to /tmp. Launched with
    /// --replay-bug2; exits the process when done.
    static func replayBug2(appState: AppState) {
        func log(_ s: String) {
            fputs(s + "\n", stderr)
            let line = (s + "\n").data(using: .utf8)!
            if let fh = FileHandle(forWritingAtPath: "/tmp/obf_replay_log") {
                fh.seekToEndOfFile()
                fh.write(line)
                try? fh.close()
            } else {
                try? line.write(to: URL(fileURLWithPath: "/tmp/obf_replay_log"))
            }
        }
        log("replayBug2: entry editor=\(appState.editor != nil)")
        guard let coordinator = appState.editor as? Coordinator,
              let textView = coordinator.debugTextView,
              let window = textView.window else {
            log("replayBug2: EARLY RETURN (coordinator/textView/window missing)")
            return
        }
        let app = NSApplication.shared
        let storage = textView.textStorage!

        /// Copies what is currently on screen without triggering a redraw.
        func snap(_ name: String) {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.bestResolution]
            ) else {
                print("snap \(name): CAPTURE FAILED")
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let pngType = NSBitmapImageRep.FileType.png
            if let data = rep.representation(using: pngType, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_snap_\(name).png"))
            }
            let markers = paragraphMarkers(storage)
            log("snap \(name): sel=\(textView.selectedRange()) storage=\(storage.string.debugDescription) markers=\(markers)")
        }

        func keyEvent(_ characters: String, _ keyCode: UInt16) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        }

        /// Sends a key event synchronously (no run-loop turn in between) and
        /// captures the backing store before and after the next display
        /// pass, so a single-frame ghost cannot slip between snapshots.
        func sendAndCapture(_ characters: String, _ keyCode: UInt16, _ name: String) {
            guard let event = keyEvent(characters, keyCode) else { return }
            app.sendEvent(event)
            snap("\(name)_pre")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.06))
            snap("\(name)_post")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Setup: H1, H2, two blank lines, one word.
            textView.insertText(
                "Заголовок\nПодзадача\n\n\ntекст",
                replacementRange: NSRange(location: 0, length: storage.length)
            )
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator.setHeadingLevel(1)
            textView.setSelectedRange(NSRange(location: 10, length: 0))
            coordinator.setHeadingLevel(2)
            snap("S0_setup")
            // Empty the H1 by holding Backspace from its end (9 chars) —
            // rapid repeats, like the user does.
            textView.setSelectedRange(NSRange(location: 9, length: 0))
            for i in 1...9 {
                sendAndCapture("\u{7F}", 51, "E\(i)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // Now "\nПодзадача\n\n\ntекст"; caret onto "текст" (loc 13) and
            // delete the blank lines above it, still hold-speed.
            textView.setSelectedRange(NSRange(location: 13, length: 0))
            snap("S1_caret_on_word")
            sendAndCapture("\u{7F}", 51, "D1")
            sendAndCapture("\u{7F}", 51, "D2")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            snap("S2_settled")
            log("REPLAY DONE storage=\(storage.string.debugDescription)")
            exit(0)
        }
    }

    /// Real-window repro for the "select text, type over it" hang/crash that
    /// only surfaces through the genuine event/drawing path. Builds the same
    /// view stack as EditorView, orders a window front, then posts actual
    /// key-down events through NSApplication. A watchdog exits 0 on success;
    /// if the main thread spins or the app crashes, the parent alarm kills
    /// the process (detected by the caller).
    static func runUITest() -> Int32 {
        let report = #selector(NSApplication.reportException)
        if let original = class_getInstanceMethod(NSApplication.self, report),
           let replacement = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.obf_reportException)) {
            method_exchangeImplementations(original, replacement)
        }
        NSSetUncaughtExceptionHandler { exception in
            print("EXCEPTION: \(exception.name) — \(exception.reason ?? "nil")")
            for line in exception.callStackSymbols.prefix(25) {
                print("    \(line)")
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appState = AppState()
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
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
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = OBFTheme.bgNS
        scrollView.borderType = .noBorder

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        appState.editor = coordinator
        coordinator.loadDocument()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        // Replace the document with deterministic content (the real file is
        // restored by the caller afterwards).
        textView.insertText(
            "Первая строка текста\nВторая строка текста\nТретья строка текста",
            replacementRange: NSRange(location: 0, length: storage.length)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let sel = textView.selectedRange()
            let ok = sel == NSRange(location: 3, length: 0)
                && storage.string == "xyz"
                && !SelfTest.uiExceptionSeen
            print("UITEST \(ok ? "OK" : "FAILED") sel=\(sel) storage=\(storage.string.debugDescription) exceptions=\(SelfTest.uiExceptionSeen)")
            exit(ok ? 0 : 1)
        }

        func postKey(_ characters: String, _ ignoring: String, _ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            app.postEvent(event, atStart: false)
        }

        // Give the window a moment to become key, then: select all, type over
        // the selection — the exact user repro.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("sel before cmd+A: \(textView.selectedRange())")
            postKey("\u{1}", "a", .command, 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("sel after cmd+A: \(textView.selectedRange())")
            postKey("x", "x", [], 7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("after typing x, sel=\(textView.selectedRange())")
            postKey("y", "y", [], 16)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            postKey("z", "z", [], 6)
        }

        app.run()
        return 0
    }
}

extension NSApplication {
    /// Swizzled over `reportException:` during --uitest to log exceptions
    /// that AppKit would otherwise only print a one-line warning for.
    @objc func obf_reportException(_ exception: NSException) {
        SelfTest.uiExceptionSeen = true
        print("REPORTED EXCEPTION: \(exception.name) — \(exception.reason ?? "nil")")
        for line in exception.callStackSymbols.prefix(30) {
            print("    \(line)")
        }
        // Original implementation (implementations were exchanged).
        obf_reportException(exception)
    }
}

extension SelfTest {
    /// Set by the swizzled reportException: during --uitest.
    static var uiExceptionSeen = false

    /// When true, the sidebar scroll monitor logs every scrollWheel event
    /// it sees — lets --uitest-open verify the gesture pipeline.
    static var loggingScrollEvents = false
    static var debugScrollLog: [String] = []

    /// Ghost-line repro: after deleting an H1, deleting the blank lines
    /// above a word leaves the word's old line on screen (drawn twice).
    /// Drives the real event path and captures the on-screen backing store
    /// (cacheDisplay performs NO redraw) right after the edit and after the
    /// debounced refresh, saving PNGs to /tmp for inspection.
    static func runUITestBug2() -> Int32 {
        let report = #selector(NSApplication.reportException)
        if let original = class_getInstanceMethod(NSApplication.self, report),
           let replacement = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.obf_reportException)) {
            method_exchangeImplementations(original, replacement)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appState = AppState()
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
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
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = OBFTheme.bgNS
        scrollView.borderType = .noBorder

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        appState.editor = coordinator
        coordinator.loadDocument()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        app.activate(ignoringOtherApps: true)
        // Prime the backing store so cacheDisplay has real content later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            window.display()
        }

        // Deterministic setup: H1, H2, two blank lines, one word.
        textView.insertText(
            "Заголовок\nПодзадача\n\n\ntекст",
            replacementRange: NSRange(location: 0, length: storage.length)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.setHeadingLevel(1)
        textView.setSelectedRange(NSRange(location: 10, length: 0))
        coordinator.setHeadingLevel(2)
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))

        /// Posts a key event; function-key characters get the .function
        /// modifier, which AppKit expects for arrows/Home/End.
        func postKey(_ characters: String, _ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16, delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var flags = modifiers
                let code = characters.unicodeScalars.first?.value ?? 0
                if code >= 0xF700 && code <= 0xF8FF {
                    flags.insert(.function)
                }
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                ) else { return }
                app.postEvent(event, atStart: false)
            }
        }

        /// Copies what is currently on screen without triggering a redraw.
        func snap(_ name: String) {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.bestResolution]
            ) else {
                print("snap \(name): CAPTURE FAILED")
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let pngType = NSBitmapImageRep.FileType.png
            if let data = rep.representation(using: pngType, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_snap_\(name).png"))
            }
            print("snap \(name): sel=\(textView.selectedRange()) storage=\(storage.string.debugDescription)")
            if let lm = textView.layoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
                var fragmentHeight: CGFloat = 0
                var fragments = 0
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in
                    fragments += 1
                }
                // measure used height via line fragment rects
                var y: CGFloat = 0
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, _, _ in
                    y = max(y, rect.maxY)
                }
                fragmentHeight = y
                let used = lm.usedRect(for: tc)
                print("    glyphs=\(lm.numberOfGlyphs)/chars=\(storage.length) fragments=\(fragments) maxY=\(fragmentHeight) usedH=\(used.height) frameH=\(textView.frame.height) boundsH=\(textView.bounds.height)")
            }
        }

        // t+0.3: baseline; select the whole H1 paragraph (text + newline)
        // and delete it with a real Backspace event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            snap("A_before")
            textView.setSelectedRange(NSRange(location: 0, length: 10))
            postKey("\u{7F}", [], 51, delay: 0.1)             // Backspace
        }
        // t+1.1: settled after H1 deletion; caret onto "текст".
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            snap("B_h1_deleted")
            textView.setSelectedRange(NSRange(location: 12, length: 0))
        }
        /// Sends a key event synchronously (no run-loop turn in between) and
        /// captures the backing store before and after the next display
        /// pass, so a single-frame ghost cannot slip between snapshots.
        func sendAndCapture(_ characters: String, _ keyCode: UInt16, _ name: String) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            app.sendEvent(event)
            snap("\(name)_1_pre_draw")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
            snap("\(name)_2_post_draw")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.6))
            snap("\(name)_3_after_debounce")
        }

        // t+1.5: caret is on "текст"; delete the blank line above it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            snap("C_caret_on_word")
            textView.setSelectedRange(NSRange(location: 12, length: 0))
            sendAndCapture("\u{7F}", 51, "D_with_h1_deleted")
        }
        // t+4.0: control run — same edit WITHOUT the prior H1 deletion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            textView.insertText(
                "Подзадача\n\n\ntекст",
                replacementRange: NSRange(location: 0, length: storage.length)
            )
            textView.setSelectedRange(NSRange(location: 10, length: 0))
            coordinator.setHeadingLevel(2)
            textView.setSelectedRange(NSRange(location: 12, length: 0))
            snap("F_control_setup")
            sendAndCapture("\u{7F}", 51, "G_no_h1_deleted")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            print("BUG2 UITEST DONE storage=\(storage.string.debugDescription) exceptions=\(SelfTest.uiExceptionSeen)")
            exit(0)
        }

        app.run()
        return 0
    }
}
