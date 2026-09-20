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

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
