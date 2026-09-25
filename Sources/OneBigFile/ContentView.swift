import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if appState.findVisible {
                    FindBar()
                        .id(appState.uiFontKey)
                }
                EditorView(appState: appState)
                    .overlay(alignment: .top) {
                        if appState.showBreadcrumb {
                            BreadcrumbBar()
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: Binding(
                get: { appState.routineEditor },
                set: { appState.routineEditor = $0 }
            )) { request in
                RoutineEditorView(request: request)
                    .environmentObject(appState)
            }

            // Always in the hierarchy (it keeps its state while hidden):
            // hiding collapses its slot to zero width, so the card slides
            // off past the right edge while fading, and the editor widens.
            SidebarView()
                // Fonts are baked into the sidebar's views; a new
                // interface font rebuilds it.
                .id(appState.uiFontKey)
                .frame(width: OBFTheme.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(SidebarCard())
                // Top edge level with the sheet's.
                .padding(.top, OBFTheme.paperTopGap)
                .padding(.leading, OBFTheme.sidebarGap)
                .opacity(appState.sidebarVisible ? 1 : 0)
                .frame(width: appState.sidebarVisible ? OBFTheme.sidebarWidth + OBFTheme.sidebarGap : 0,
                       alignment: .leading)
                .allowsHitTesting(appState.sidebarVisible)
        }
        .animation(OBFTheme.sidebarAnimation, value: appState.sidebarVisible)
        .padding(OBFTheme.contentPadding)
        .frame(width: OBFTheme.windowWidth, height: OBFTheme.windowHeight)
        // The desk around the sheet (re-read when the sheet style changes).
        .background(OBFTheme.desk)
        .overlay {
            TabPickerOverlay()
                .id(appState.uiFontKey)
        }
        .sheet(isPresented: Binding(
            get: { appState.modalTaskID != nil },
            set: { if !$0 { appState.modalTaskID = nil } }
        )) {
            TaskModalView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            appState.refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshToday()
        }
        .onAppear {
            RoutineKeys.install(appState: appState)
            if CommandLine.arguments.contains("--replay-bug2") {
                SelfTest.replayBug2(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-outline") {
                SelfTest.snapOutline(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-sidebar") {
                SelfTest.snapSidebar(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-themes") {
                SelfTest.snapThemes(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-typography") {
                SelfTest.snapTypography(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-demo") {
                RoutineDemo.snapshot(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-routine") {
                SelfTest.snapRoutine(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-open") {
                SelfTest.measureOpen(appState: appState)
            }
        }
    }
}

/// Cmd+K: the window dims and a card lists every sidebar tab. Arrows +
/// Return, a digit 1…7 or the tab's letter open it (the sidebar slides in
/// if it was hidden); Esc or a click outside closes.
struct TabPickerOverlay: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if appState.tabPickerVisible {
                Color.black.opacity(OBFTheme.theme.isDark ? 0.45 : 0.25)
                    .contentShape(Rectangle())
                    .onTapGesture { appState.hideTabPicker() }
                    .transition(.opacity)
                TabPickerCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: appState.tabPickerVisible)
    }
}

private struct TabPickerCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text("Перейти к разделу")
                .font(OBFTheme.ui(12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(Array(SidebarTab.allCases.enumerated()), id: \.element) { index, tab in
                row(tab, index: index)
            }
            Text("↑↓ и ⏎  ·  цифра 1–7  ·  буква  ·  Esc — закрыть")
                .font(OBFTheme.ui(11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
        }
        .padding(12)
        .frame(width: 340)
        .background(shape.fill(OBFTheme.paper))
        .overlay(shape.stroke(OBFTheme.paperBorder, lineWidth: 1))
        .shadow(color: .black.opacity(OBFTheme.theme.shadow + 0.1), radius: 30, x: 0, y: 12)
        .animation(.easeOut(duration: 0.1), value: appState.tabPickerIndex)
    }

    private func row(_ tab: SidebarTab, index: Int) -> some View {
        let highlighted = appState.tabPickerIndex == index
        return HStack(spacing: 10) {
            KeyCap(text: "\(index + 1)")
            Text(tab.title)
                .font(OBFTheme.ui(15))
                .foregroundColor(OBFTheme.text)
            if tab == appState.sidebarTab {
                Circle()
                    .fill(OBFTheme.h1Text)
                    .frame(width: 5, height: 5)
                    .help("Открыт сейчас")
            }
            Spacer(minLength: 8)
            KeyCap(text: tab.shortcutLetter)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(highlighted ? OBFTheme.selection.opacity(0.45) : Color.clear))
        .contentShape(Rectangle())
        .onHover { if $0 { appState.tabPickerIndex = index } }
        .onTapGesture { appState.openSidebarTab(tab) }
    }
}

/// A small keyboard key label ("1", "S").
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(.secondary)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(OBFTheme.hover))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(OBFTheme.border, lineWidth: 1))
    }
}

/// The sidebar's surface: a card floating over the desk — rounded, a
/// hairline edge and a soft shadow, in the sheet's colour so the cards
/// inside stand apart from it.
struct SidebarCard: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: OBFTheme.sidebarCornerRadius, style: .continuous)
        shape
            .fill(OBFTheme.paper)
            .overlay(shape.stroke(OBFTheme.paperBorder, lineWidth: 1))
            .shadow(color: .black.opacity(OBFTheme.theme.shadow * 0.9), radius: 20, x: 0, y: 8)
    }
}

/// Pinned over the top of the editor while scrolling: the H1 and H2 the
/// visible text belongs to, e.g. "Магистратура 1 семестр › Аналитические
/// модели АСОИУ". Clicking a part jumps to that heading. Fades in and out.
struct BreadcrumbBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            if let crumb = appState.breadcrumb {
                HStack(spacing: 7) {
                    if let h1 = crumb.h1 {
                        part(h1, color: OBFTheme.h1Text)
                    }
                    if crumb.h1 != nil && crumb.h2 != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    if let h2 = crumb.h2 {
                        part(h2, color: OBFTheme.text)
                    }
                    Spacer(minLength: 0)
                }
                .font(OBFTheme.ui(12))
                .lineLimit(1)
                .frame(maxWidth: OBFTheme.textColumnWidth)
                .padding(.horizontal, 25)
                .frame(height: Coordinator.breadcrumbHeight)
                // Exactly the sheet's width (see OBFTextView.paperRect).
                .frame(maxWidth: OBFTheme.textColumnWidth + 2 * OBFTheme.paperPadding - 10)
                .background(
                    // The sheet's colour, fading out below the bar.
                    LinearGradient(stops: [
                        .init(color: OBFTheme.paper, location: 0),
                        .init(color: OBFTheme.paper, location: 0.75),
                        .init(color: OBFTheme.paper.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .padding(.bottom, -10))
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: appState.breadcrumb == nil)
        .animation(.easeInOut(duration: 0.12), value: appState.breadcrumb)
    }

    private func part(_ item: OutlineItem, color: Color) -> some View {
        Button {
            appState.editor?.scrollToOutline(item)
        } label: {
            Text(item.title.isEmpty ? "—" : item.title)
                .foregroundColor(color.opacity(0.85))
                .truncationMode(.tail)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Перейти к заголовку")
    }
}

/// Direction of a sidebar tab switch.
enum SidebarTabMove: Equatable {
    case next, prev
}

/// Recognizes a deliberate two-finger horizontal swipe from a trackpad's
/// scroll-event stream. NSEventTypeSwipe gestures are only generated when
/// the system "swipe between pages" setting produces them (turning that
/// setting OFF removes swipe events entirely), so tabs are driven off
/// scroll phases instead — the same technique browsers use for trackpad
/// back/forward. Vertical scrolling and mouse wheels never trigger:
/// trackpad gestures carry phases, and the swipe must be strongly
/// horizontal-dominant.
struct HorizontalSwipeRecognizer {
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var triggered = false

    /// Horizontal travel beyond which the swipe fires, in points.
    static let threshold: CGFloat = 60

    mutating private func reset() {
        accumulatedX = 0
        accumulatedY = 0
        triggered = false
    }

    /// Leftward swipe (fingers move left) reports .next, rightward .prev.
    /// Fires at most once per gesture; returns nil while inconclusive.
    mutating func handle(phase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat) -> SidebarTabMove? {
        if phase.contains(.began) {
            reset()
        }
        guard !triggered else { return nil }
        guard phase.contains(.began) || phase.contains(.changed) else { return nil }
        accumulatedX += deltaX
        accumulatedY += deltaY
        guard abs(accumulatedX) > HorizontalSwipeRecognizer.threshold,
              abs(accumulatedX) > abs(accumulatedY) * 1.5 else { return nil }
        triggered = true
        // Natural scrolling: fingers moving left produce negative deltas.
        return accumulatedX < 0 ? .next : .prev
    }
}

/// Class box so the scroll monitor's closure can mutate recognizer state
/// (a captured struct value would freeze at install time).
private final class SidebarGestureBox {
    var recognizer = HorizontalSwipeRecognizer()
}

/// One task block: creation date, a clickable two-line header (line 1:
/// H1 with a Roman "I", bold; line 2: H2 with a Roman "II"; a missing
/// level leaves its line blank) that jumps to the task in the document,
/// and the task text in a bordered box with a chevron that smoothly
/// expands it. Collapsed cards all have the same fixed layout: two lines
/// reserved for the header and two for the task text, long values are
/// tail-truncated on their own line. Tapping the text (or the chevron)
/// expands it — up to eight lines; longer texts scroll inside the box.
/// While the task is being typed in the editor, the card gently wiggles
/// and shows a steady "Печатаем задание" placeholder instead of rewriting
/// the text on every debounced refresh.
struct TaskCardView: View {
    @EnvironmentObject private var appState: AppState
    let task: SidebarTaskItem
    let typing: Bool
    let expanded: Bool
    let toggleExpanded: () -> Void

    /// Expanded text is capped at this many lines; longer texts scroll.
    static let maxExpandedLines = 8

    var body: some View {
        // The wiggle is driven by wall-clock time rather than a repeating
        // animation: a repeatForever animation started while typing gets
        // stuck on the card when the typing flag flips mid-oscillation.
        if typing {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                cardContent
                    .rotationEffect(.degrees(sin(context.date.timeIntervalSinceReferenceDate * 9) * 1.4))
            }
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.displayDate(task.created))
                .font(OBFTheme.ui(12))
                .foregroundColor(.secondary)

            Button {
                appState.editor?.scrollToTask(task)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.h1.map { "I \($0)" } ?? (task.h2 == nil ? "Без заголовков" : " "))
                        .font(task.h1 != nil
                              ? OBFTheme.uiBold(13)
                              : OBFTheme.ui(13))
                        .foregroundColor(task.h1 != nil ? OBFTheme.text : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(task.h2.map { "II \($0)" } ?? " ")
                        .font(OBFTheme.ui(13))
                        .foregroundColor(OBFTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity,
                       minHeight: Self.lineHeight(13) * 2, maxHeight: Self.lineHeight(13) * 2,
                       alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 8) {
                Group {
                    if expanded && canExpand {
                        TrappedTaskTextView(
                            text: displayedText,
                            placeholderStyle: typing || task.text.isEmpty,
                            onTap: toggleExpanded)
                            .frame(height: expandedHeight)
                    } else {
                        textContent
                            .lineLimit(2)
                            .frame(height: Self.lineHeight(14) * 2, alignment: .topLeading)
                            .contentShape(Rectangle())
                            .onTapGesture { if canExpand { toggleExpanded() } }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if canExpand {
                    Button(action: toggleExpanded) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(OBFTheme.text)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(OBFTheme.bg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OBFTheme.border, lineWidth: 1)
            )
        }
        .padding(10)
        .background(OBFTheme.elevated)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OBFTheme.border, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            OpenTaskButton { appState.modalTaskID = task.id }
                .padding(7)
        }
        .opacity(task.done ? 0.5 : 1)
    }

    /// Whether the text needs more than the collapsed two lines. Short
    /// texts get no chevron and do not expand. Measured on the task's own
    /// text (not the typing placeholder), so the chevron does not flicker
    /// while the task is being typed.
    private var canExpand: Bool {
        Self.needsExpansion(task.text.isEmpty ? "Новое задание" : task.text)
    }

    static func needsExpansion(_ text: String) -> Bool {
        fullTextHeight(text) > lineHeight(14) * 2 + 0.5
    }

    private var displayedText: String {
        typing ? "Печатаем задание" : (task.text.isEmpty ? "Новое задание" : task.text)
    }

    private var textContent: some View {
        Text(displayedText)
            .font(OBFTheme.ui(14))
            .italic(typing)
            .foregroundColor(typing || task.text.isEmpty ? .secondary : OBFTheme.text)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Full text height clamped between the collapsed two-line height and
    /// the expanded cap; past the cap the box scrolls.
    private var expandedHeight: CGFloat {
        Self.expandedHeight(for: displayedText)
    }

    static func expandedHeight(for text: String) -> CGFloat {
        let line = lineHeight(14)
        let full = fullTextHeight(text)
        return max(line * 2, min(full, line * CGFloat(maxExpandedLines)))
    }

    /// Width of the task-text column: the fixed sidebar width minus the
    /// list padding, the card padding, the text-box padding and the
    /// chevron column.
    private static var textColumnWidth: CGFloat {
        OBFTheme.sidebarWidth - 2 * 14 - 2 * 10 - 2 * 8 - 8 - 20
    }

    static func fullTextHeight(_ text: String) -> CGFloat {
        textHeight(text, size: 14, width: textColumnWidth)
    }

    static func textHeight(_ text: String, size: CGFloat, width: CGFloat) -> CGFloat {
        let font = OBFTheme.uiNSFont(size: size)
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return ceil(rect.height)
    }

    /// Height of one line of the app font at `size`, so cards reserve
    /// space for lines even when the value fits on fewer.
    static func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = OBFTheme.uiNSFont(size: size)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// "yyyy-MM-dd" -> "dd-MM-yyyy"; a single space for dateless tasks so
    /// every card keeps the same height.
    static func displayDate(_ raw: String?) -> String {
        guard let raw else { return " " }
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(parts[2])-\(parts[1])-\(parts[0])"
    }
}

/// An NSScrollView that consumes scroll-wheel events at its edges instead
/// of forwarding them up the responder chain: while the pointer rests on
/// an expanded task text, the sidebar's own scroll view must never start
/// scrolling when the text can no longer move in the requested direction.
/// Scrolling is applied manually (not via super) so the behaviour is
/// identical for real trackpad events and for synthetic test events.
final class TrappedScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let offset = contentView.bounds.origin.y
        let maxOffset = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        let inverted = event.isDirectionInvertedFromDevice
        guard Self.shouldScroll(offset: offset, maxOffset: maxOffset,
                                deltaY: delta, inverted: inverted)
        else { return }
        // At the edge the event is eaten — never forwarded, so the sidebar
        // stays put.
        let towardBottom = Self.isTowardBottom(deltaY: delta, inverted: inverted)
        let newOffset = towardBottom
            ? min(maxOffset, offset + abs(delta))
            : max(0, offset - abs(delta))
        contentView.setBoundsOrigin(NSPoint(x: 0, y: newOffset))
        reflectScrolledClipView(contentView)
    }

    /// True when the content can still move in the event's direction.
    static func shouldScroll(offset: CGFloat, maxOffset: CGFloat, deltaY: CGFloat, inverted: Bool) -> Bool {
        let towardBottom = isTowardBottom(deltaY: deltaY, inverted: inverted)
        return towardBottom ? offset < maxOffset - 0.5 : offset > 0.5
    }

    /// Scroll direction inside the task text is reversed relative to the
    /// system setting: fingers moving up reveal the text further down.
    static func isTowardBottom(deltaY: CGFloat, inverted: Bool) -> Bool {
        inverted ? deltaY < 0 : deltaY > 0
    }

    /// True when a window point lies over an expanded task text box.
    static func contains(windowPoint: NSPoint, in root: NSView) -> Bool {
        if let trap = root as? TrappedScrollView, !trap.isHiddenOrHasHiddenAncestor {
            return trap.convert(trap.bounds, to: nil).contains(windowPoint)
        }
        return root.subviews.contains { contains(windowPoint: windowPoint, in: $0) }
    }
}

/// Top-left origin, so scroll offset 0 is the text's first line.
final class FlippedTextView: NSTextView {
    override var isFlipped: Bool { true }
}

/// Expanded task text in a scrollable AppKit box (see TrappedScrollView).
/// Clicking the text collapses the card.
private struct TrappedTaskTextView: NSViewRepresentable {
    let text: String
    /// Italic secondary style of the "Печатаем задание" placeholder.
    let placeholderStyle: Bool
    var fontSize: CGFloat = 14
    var textColor: NSColor = OBFTheme.textNS
    /// Selectable text is for reading and copying (the task modal); the
    /// sidebar card instead collapses on click.
    var selectable = false
    var onTap: (() -> Void)?

    final class ClickTarget: NSObject {
        var onTap: () -> Void = {}
        @objc func handleClick() { onTap() }
    }

    func makeCoordinator() -> ClickTarget { ClickTarget() }

    func makeNSView(context: Context) -> TrappedScrollView {
        let scrollView = TrappedScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = FlippedTextView()
        textView.isEditable = false
        textView.isSelectable = selectable
        textView.selectedTextAttributes = [.backgroundColor: OBFTheme.selectionNS]
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView

        if onTap != nil {
            let click = NSClickGestureRecognizer(
                target: context.coordinator, action: #selector(ClickTarget.handleClick))
            scrollView.addGestureRecognizer(click)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: TrappedScrollView, context: Context) {
        context.coordinator.onTap = onTap ?? {}
        guard let textView = scrollView.documentView as? FlippedTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        let base = OBFTheme.uiNSFont(size: fontSize)
        textView.font = placeholderStyle
            ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            : base
        textView.textColor = placeholderStyle ? .secondaryLabelColor : textColor
    }
}

/// Small square button in a task card's top-right corner that opens the
/// task in the modal.
private struct OpenTaskButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(hovering ? OBFTheme.text : .secondary)
                .frame(width: 20, height: 20)
                .background(hovering ? OBFTheme.border : OBFTheme.bg)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(OBFTheme.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Открыть задание целиком")
    }
}

/// Full-size view of one task, presented as a sheet over the main window
/// (so the editor cannot be typed into while it is open; Esc closes it).
/// Shows the status, creation date, location (H1 / H2) and the whole task
/// text — selectable, scrolling inside the box when it is very long.
/// Active and done tasks differ in accent colour, badge and text styling.
struct TaskModalView: View {
    @EnvironmentObject private var appState: AppState

    static let width: CGFloat = 600
    private static let textSize: CGFloat = 16
    /// Horizontal padding of the sheet and of the text box inside it.
    private static let padding: CGFloat = 24
    private static let boxPadding: CGFloat = 14
    private static let maxTextLines = 18

    var body: some View {
        Group {
            if let task = appState.modalTask {
                content(task)
            } else {
                // The task vanished from the document; nothing to show.
                Color.clear.frame(width: Self.width, height: 1)
                    .onAppear { appState.modalTaskID = nil }
            }
        }
        .presentationBackground(OBFTheme.elevated)
        .preferredColorScheme(OBFTheme.colorScheme)
    }

    private func content(_ task: SidebarTaskItem) -> some View {
        let accent = task.done ? OBFTheme.done : OBFTheme.h1Text
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    statusBadge(done: task.done, accent: accent)
                    Spacer()
                    if let created = task.created {
                        Label(TaskCardView.displayDate(created), systemImage: "calendar")
                            .font(OBFTheme.ui(13))
                            .foregroundColor(.secondary)
                    }
                }

                location(task)

                textBox(task, accent: accent)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Закрыть") { appState.modalTaskID = nil }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(ModalButtonStyle(filled: false, accent: accent))
                    Button("Перейти к заданию") {
                        appState.modalTaskID = nil
                        appState.editor?.scrollToTask(task)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(ModalButtonStyle(filled: true, accent: accent))
                }
            }
            .padding(Self.padding)
        }
        .frame(width: Self.width)
        .background(OBFTheme.elevated)
    }

    private func statusBadge(done: Bool, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 12, weight: .semibold))
            Text(done ? "Выполнено" : "Активное задание")
                .font(OBFTheme.uiBold(13))
        }
        .foregroundColor(accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(accent.opacity(0.14))
        .cornerRadius(6)
    }

    /// Where the task lives in the document: its H1 and H2 headings, laid
    /// out like the sidebar card ("I …" / "II …") but untruncated.
    @ViewBuilder private func location(_ task: SidebarTaskItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Расположение")
                .font(OBFTheme.ui(12))
                .foregroundColor(.secondary)
            if task.h1 == nil && task.h2 == nil {
                Text("Без заголовков")
                    .font(OBFTheme.ui(15))
                    .foregroundColor(.secondary)
            }
            if let h1 = task.h1 {
                Text("I \(h1)")
                    .font(OBFTheme.uiBold(18))
                    .foregroundColor(OBFTheme.h1Text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let h2 = task.h2 {
                Text("II \(h2)")
                    .font(OBFTheme.ui(15))
                    .foregroundColor(OBFTheme.text)
                    .padding(.leading, task.h1 == nil ? 0 : 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }

    private func textBox(_ task: SidebarTaskItem, accent: Color) -> some View {
        let text = task.text.isEmpty ? "Новое задание" : task.text
        let width = Self.width - 2 * Self.padding - 2 * Self.boxPadding - 3
        let line = TaskCardView.lineHeight(Self.textSize)
        let full = TaskCardView.textHeight(text, size: Self.textSize, width: width)
        let height = max(line, min(full, line * CGFloat(Self.maxTextLines)))
        return TrappedTaskTextView(
            text: text,
            placeholderStyle: task.text.isEmpty,
            fontSize: Self.textSize,
            // Done tasks read as finished: dimmer text on a quiet box.
            textColor: task.done ? OBFTheme.textNS.withAlphaComponent(0.7) : OBFTheme.textNS,
            selectable: true)
            .frame(height: height)
            .padding(Self.boxPadding)
            .padding(.leading, 3)
            .background(OBFTheme.bg)
            .overlay(alignment: .leading) {
                // Accent bar on the left edge of the text.
                Rectangle().fill(accent.opacity(task.done ? 0.5 : 1)).frame(width: 3)
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OBFTheme.border, lineWidth: 1)
            )
    }
}

struct ModalButtonStyle: ButtonStyle {
    let filled: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OBFTheme.ui(14))
            .foregroundColor(filled ? OBFTheme.bg : OBFTheme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(filled ? accent : OBFTheme.bg)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(filled ? Color.clear : OBFTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var hoveringTitle = false
    @State private var hoveringList = false
    @State private var gestureBox = SidebarGestureBox()
    @State private var scrollMonitor: Any?

    private var tabListVisible: Bool { hoveringTitle || hoveringList }

    var body: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(appState.sidebarTab)
                .transition(.opacity)

            tabBar
        }
        .animation(.easeInOut(duration: 0.15), value: appState.sidebarTab)
        .onAppear {
            installScrollMonitor()
        }
        .onDisappear {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
            }
            scrollMonitor = nil
        }
    }

    // MARK: - Tab content

    @ViewBuilder private var tabContent: some View {
        switch appState.sidebarTab {
        case .structure where !appState.outline.isEmpty:
            outlineContent
        case .tasks:
            tasksContent
        case .routine:
            RoutineView()
        default:
            emptyPlaceholder
        }
    }

    private var emptyPlaceholder: some View {
        Text("Здесь пока пусто")
            .font(OBFTheme.ui(14))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outlineContent: some View {
        OutlineView()
    }

    // MARK: - Tasks tab

    private var tasksContent: some View {
        // The ScrollView stays in the hierarchy even when empty, so the
        // very first card gets the same insertion animation as later ones;
        // the placeholder floats above the empty list and fades in/out.
        ZStack {
            ScrollView {
                // A single VStack (not lazy) over one ForEach keyed by the
                // tasks' stable uids: appearing cards fade in with a slight
                // scale-and-drop, a done-toggle animates the card's springy
                // move to the other section, removed cards fade and shrink.
                VStack(alignment: .leading, spacing: 10) {
                    let firstActiveID = appState.tasks.first(where: { !$0.done })?.id
                    let firstDoneID = appState.tasks.first(where: { $0.done })?.id
                    let doneCount = appState.tasks.filter(\.done).count
                    let activeCount = appState.tasks.count - doneCount
                    ForEach(appState.tasks) { task in
                        if !task.done, task.id == firstActiveID {
                            sectionHeader("Активные", count: activeCount)
                        }
                        if task.done, task.id == firstDoneID {
                            sectionHeader("Выполненные", count: doneCount)
                                .padding(.top, activeCount > 0 ? 8 : 0)
                        }
                        TaskCardView(
                            task: task,
                            typing: appState.editingTaskLocation == task.range.location,
                            expanded: appState.expandedTaskID == task.id,
                            toggleExpanded: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.expandedTaskID = appState.expandedTaskID == task.id ? nil : task.id
                                }
                            })
                            .transition(.asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.9, anchor: .top))
                                    .combined(with: .offset(y: -10)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.9, anchor: .top))))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: appState.tasks)
                .padding(14)
            }
            if appState.tasks.isEmpty {
                emptyPlaceholder
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.tasks.isEmpty)
    }

    /// Section title over the active / done task cards with the live
    /// number of cards in that section, e.g. "Активные (10)".
    private func sectionHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(OBFTheme.ui(13))
            .foregroundColor(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .transition(.opacity)
    }

    // MARK: - Bottom tab bar

    private var tabBar: some View {
        HStack(spacing: 26) {
            Button {
                appState.selectPrevSidebarTab()
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(appState.sidebarTab.title)
                .font(OBFTheme.ui(17))
                .foregroundColor(OBFTheme.text)
                // The padded, shape-extended title is the hover zone; it
                // reaches the bar's top edge so the cursor can travel into
                // the floating list without the hover dropping in between.
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onHover { hoveringTitle = $0 }

            Button {
                appState.selectNextSidebarTab()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .font(.system(size: 15, weight: .light))
        .foregroundColor(OBFTheme.text)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if tabListVisible {
                // Bar height is 48 (17 pt text + 16 title padding + 12 bar
                // padding); 44 lifts the list just above it with a slight
                // overlap into the title's hover zone — no gap.
                tabList
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: tabListVisible)
        .zIndex(1)
    }

    /// All tabs except the current one, last-first — the list opens upward
    /// from the tab title, so the next tab ends up closest to the cursor.
    private var tabList: some View {
        VStack(spacing: 10) {
            ForEach(SidebarTab.allCases.reversed().filter { $0 != appState.sidebarTab }) { tab in
                Button {
                    appState.sidebarTab = tab
                    hoveringTitle = false
                    hoveringList = false
                } label: {
                    Text(tab.title)
                        .font(OBFTheme.ui(16))
                        .foregroundColor(OBFTheme.text)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(OBFTheme.elevated)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OBFTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .onHover { hoveringList = $0 }
        .fixedSize()
    }

    // MARK: - Two-finger swipe

    /// Two-finger horizontal swipe over the sidebar: fingers left advance
    /// to the next tab, fingers right go back to the previous one. Driven
    /// off scrollWheel events with gesture phases — NSEventTypeSwipe is not
    /// generated at all when "swipe between pages" is off in System
    /// Settings. Installed as a local monitor because SwiftUI views are not
    /// part of the AppKit responder chain that receives gesture events.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [appState, gestureBox] event in
            if SelfTest.loggingScrollEvents {
                SelfTest.debugScrollLog.append(
                    "phase=\(event.phase.rawValue) dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) loc=\(event.locationInWindow)"
                )
            }
            // Mouse wheels and momentum phases carry no gesture phase.
            guard event.phase != [] else { return event }
            // A hidden sidebar takes no gestures.
            guard appState.sidebarVisible else { return event }
            // Modals are sheet windows; their gestures never switch tabs.
            guard !appState.anyModalOpen else { return event }
            // Synthetic posted events have no associated window; for them
            // locationInWindow is a screen point. Real gesture events are
            // always window-relative already.
            let location: NSPoint
            if event.window != nil {
                location = event.locationInWindow
            } else if let window = NSApp.keyWindow ?? NSApp.windows.first {
                location = window.convertPoint(fromScreen: event.locationInWindow)
            } else {
                return event
            }
            // The window layout is fixed and not resizable: the sidebar is
            // the rightmost sidebarWidth points of the content, inset by
            // the content padding (see OBFTheme).
            let sidebar = CGRect(
                x: OBFTheme.windowWidth - OBFTheme.contentPadding - OBFTheme.sidebarWidth,
                y: OBFTheme.contentPadding,
                width: OBFTheme.sidebarWidth,
                height: OBFTheme.windowHeight - OBFTheme.contentPadding * 2
            )
            guard sidebar.contains(location) else { return event }
            // Over an expanded task text, two-finger gestures only scroll
            // the text — they never switch tabs.
            if let root = (event.window ?? NSApp.keyWindow ?? NSApp.windows.first)?.contentView,
               TrappedScrollView.contains(windowPoint: location, in: root) {
                return event
            }
            switch gestureBox.recognizer.handle(
                phase: event.phase,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            ) {
            case .next:
                appState.selectNextSidebarTab()
            case .prev:
                appState.selectPrevSidebarTab()
            case nil:
                break
            }
            return event
        }
    }
}

struct FindBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Найти", text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(OBFTheme.text)
                .focused($isFocused)
                .onSubmit {
                    appState.editor?.findNext()
                }

            Text(appState.matchCounterText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary)

            Button {
                appState.editor?.findPrev()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)

            Button {
                appState.editor?.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)

            Button {
                appState.closeFind()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(OBFTheme.text)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OBFTheme.border).frame(height: 1)
        }
        .onAppear {
            isFocused = true
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
                // Keys belong to the modal while one is open.
                guard !appState.anyModalOpen else { return event }
                if event.keyCode == 53 {
                    appState.closeFind()
                    return nil
                }
                let isReturn = event.keyCode == 36 || event.keyCode == 76
                // SwiftUI's find field is a private NSText subclass that the
                // window does not register as its field editor, so detect it
                // as "any NSText that is not the document text view".
                if isReturn, let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSText, !(responder is OBFTextView) {
                    if event.modifierFlags.contains(.shift) {
                        appState.editor?.findPrev()
                    } else {
                        appState.editor?.findNext()
                    }
                    return nil
                }
                return event
            }
        }
        .onChange(of: appState.findFocusRequest) {
            isFocused = true
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { appState.findQuery },
            set: { newValue in
                // SwiftUI commits the field text back to the binding on Return
                // with the same value — that must not restart the search,
                // otherwise Enter keeps resetting the match index to 0.
                guard newValue != appState.findQuery else { return }
                appState.findQuery = newValue
                appState.editor?.updateFindMatches()
            }
        )
    }
}
