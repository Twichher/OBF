import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        if CommandLine.arguments.contains("--uitest") {
            exit(SelfTest.runUITest())
        }
        if CommandLine.arguments.contains("--uitest-bug2") {
            exit(SelfTest.runUITestBug2())
        }
        if CommandLine.arguments.contains("--replay-bug2")
            || CommandLine.arguments.contains("--uitest-open")
            || CommandLine.arguments.contains("--uitest-routine")
            || CommandLine.arguments.contains("--demo-routine")
            || CommandLine.arguments.contains("--uitest-demo")
            || CommandLine.arguments.contains("--uitest-typography")
            || CommandLine.arguments.contains("--uitest-themes")
            || CommandLine.arguments.contains("--uitest-sidebar")
            || CommandLine.arguments.contains("--uitest-outline") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct OneBigFileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState = OneBigFileApp.makeAppState()

    /// UI-test modes that drive the real window (--uitest-open,
    /// --replay-bug2) swap demo content in and out; they must never touch
    /// the real document, so they get a throwaway store in /tmp.
    private static func makeAppState() -> AppState {
        let args = CommandLine.arguments
        if args.contains("--uitest-typography") || args.contains("--uitest-themes") || args.contains("--uitest-sidebar")
            || args.contains("--uitest-outline") {
            // A throwaway copy of the real document and routine: the
            // snapshots show real content without touching it.
            let doc = URL(fileURLWithPath: "/tmp/obf_typo_document.md")
            let routine = URL(fileURLWithPath: "/tmp/obf_typo_routine.json")
            let real = DocumentStore().fileURL
            for (from, to) in [(real, doc), (real.deletingLastPathComponent().appendingPathComponent("routine.json"), routine)] {
                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.copyItem(at: from, to: to)
            }
            return AppState(store: DocumentStore(fileURL: doc), routineStore: RoutineStore(fileURL: routine))
        }
        if args.contains("--demo-routine") || args.contains("--uitest-demo") {
            return RoutineDemo.makeAppState()
        }
        if args.contains("--uitest-routine") {
            let routineURL = URL(fileURLWithPath: "/tmp/obf_uitest_routine.json")
            try? FileManager.default.removeItem(at: routineURL)
            return AppState(
                store: DocumentStore(fileURL: URL(fileURLWithPath: "/tmp/obf_uitest_document.md")),
                routineStore: RoutineStore(fileURL: routineURL))
        }
        if args.contains("--uitest-open") || args.contains("--replay-bug2") {
            return AppState(store: DocumentStore(fileURL: URL(fileURLWithPath: "/tmp/obf_uitest_document.md")))
        }
        return AppState()
    }

    var body: some Scene {
        Window("One Big File", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(width: OBFTheme.windowWidth, height: OBFTheme.windowHeight)
                .preferredColorScheme(OBFTheme.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.editor?.saveNow()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    appState.editor?.saveNow()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Вид") {
                Button("Увеличить шрифт") {
                    appState.editor?.zoomIn()
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])

                Button("Уменьшить шрифт") {
                    appState.editor?.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Picker("Шрифт текста", selection: $appState.editorFont) {
                    ForEach(EditorFont.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }

                Toggle("Интерфейс шрифтом текста", isOn: $appState.uiFollowsEditor)

                Toggle("Хлебные крошки", isOn: $appState.showBreadcrumb)

                Divider()

                Picker("Тема", selection: $appState.themeID) {
                    ForEach(ColorTheme.all) { theme in
                        Text(theme.title).tag(theme.id)
                    }
                }
            }

            CommandMenu("Сайдбар") {
                Button(appState.sidebarVisible ? "Скрыть сайдбар" : "Показать сайдбар") {
                    appState.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Перейти к разделу…") {
                    appState.showTabPicker()
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                ForEach(SidebarTab.allCases) { tab in
                    Button(tab.title) {
                        if tab == .routine {
                            appState.showRoutine(day: nil)
                        } else {
                            appState.openSidebarTab(tab)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character(tab.shortcutLetter.lowercased())),
                                      modifiers: tab == .routine ? .command : [.command, .shift])
                }
            }

            CommandMenu("Структура") {
                Button("Заголовок 1 уровня") {
                    appState.editor?.setHeadingLevel(1)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Заголовок 2 уровня") {
                    appState.editor?.setHeadingLevel(2)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Обычный текст") {
                    appState.editor?.setHeadingLevel(0)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Задание") {
                    appState.editor?.toggleTask()
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Задание выполнено") {
                    appState.editor?.toggleTaskDone()
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Список") {
                    appState.editor?.toggleList()
                }
                .keyboardShortcut("5", modifiers: .command)

                Divider()

                Button("Найти…") {
                    appState.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
