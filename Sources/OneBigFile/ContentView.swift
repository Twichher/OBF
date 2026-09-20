import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if appState.findVisible {
                    FindBar()
                }
                EditorView(appState: appState)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(OBFTheme.border)
                .frame(width: 1)

            SidebarView()
                .frame(width: OBFTheme.sidebarWidth)
                .frame(maxHeight: .infinity)
        }
        .padding(OBFTheme.contentPadding)
        .frame(width: OBFTheme.windowWidth, height: OBFTheme.windowHeight)
        .background(OBFTheme.bg)
        .onAppear {
            if CommandLine.arguments.contains("--replay-bug2") {
                SelfTest.replayBug2(appState: appState)
            }
            if CommandLine.arguments.contains("--uitest-open") {
                SelfTest.measureOpen(appState: appState)
            }
        }
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
        default:
            emptyPlaceholder
        }
    }

    private var emptyPlaceholder: some View {
        Text("Здесь пока пусто")
            .font(.custom(OBFTheme.fontName, size: 14))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outlineContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(appState.outline) { item in
                    Button {
                        appState.editor?.scrollToOutline(item)
                    } label: {
                        Text(item.title.isEmpty ? "—" : item.title)
                            .font(item.level == 1
                                  ? Font.custom(OBFTheme.fontName, size: 16).bold()
                                  : Font.custom(OBFTheme.fontName, size: 14))
                            .foregroundColor(OBFTheme.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, item.level == 2 ? 20 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: appState.outline)
            .padding(14)
        }
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
                .font(.custom(OBFTheme.fontName, size: 17))
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
                        .font(.custom(OBFTheme.fontName, size: 16))
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
