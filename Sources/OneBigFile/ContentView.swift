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
                .frame(width: 260)
                .frame(maxHeight: .infinity)
        }
        .padding(16)
        .frame(width: 1200, height: 800)
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

/// Sidebar frame in window coordinates, reported upward so the swipe-event
/// monitor can tell whether the gesture happened over the sidebar.
private struct SidebarFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Class box so the swipe monitor's closure always reads the current frame
/// (a captured struct value would freeze at install time).
private final class SidebarFrameBox {
    var value: CGRect = .zero
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var hoveringTitle = false
    @State private var hoveringList = false
    @State private var frameBox = SidebarFrameBox()
    @State private var swipeMonitor: Any?

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
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SidebarFrameKey.self, value: geo.frame(in: .global))
            }
        )
        .onPreferenceChange(SidebarFrameKey.self) { frameBox.value = $0 }
        .onAppear {
            installSwipeMonitor()
        }
        .onDisappear {
            if let swipeMonitor {
                NSEvent.removeMonitor(swipeMonitor)
            }
            swipeMonitor = nil
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

    /// Two-finger swipe over the sidebar: left advances to the next tab,
    /// right goes back to the previous one. Swipe events travel the AppKit
    /// responder chain, which SwiftUI sidebar views are not part of, so a
    /// local monitor checks the gesture location against the sidebar frame.
    private func installSwipeMonitor() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [appState, frameBox] event in
            guard let window = event.window,
                  let content = window.contentView else { return event }
            let global = frameBox.value
            // .global is top-left based; event locations are bottom-left based.
            let cocoa = CGRect(
                x: global.minX,
                y: content.bounds.height - global.maxY,
                width: global.width,
                height: global.height
            )
            guard cocoa.contains(event.locationInWindow) else { return event }
            if event.deltaX < 0 {
                appState.selectNextSidebarTab()
                return nil
            }
            if event.deltaX > 0 {
                appState.selectPrevSidebarTab()
                return nil
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
