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
            || CommandLine.arguments.contains("--uitest-open") {
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
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("One Big File", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(width: 1200, height: 800)
                .preferredColorScheme(.dark)
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

                Divider()

                Button("Найти…") {
                    appState.showFindBar()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
