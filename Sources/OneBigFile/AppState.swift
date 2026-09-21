import AppKit

struct OutlineItem: Identifiable, Equatable {
    let title: String
    let level: Int
    let range: NSRange

    // Location-based identity stays stable while a heading is edited, so the
    // sidebar can animate insertions and removals instead of rebuilding the
    // whole list on every refresh.
    var id: Int { range.location }

    static func == (lhs: OutlineItem, rhs: OutlineItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.level == rhs.level
    }
}

/// A task paragraph as shown in the sidebar's "Задания" tab.
struct SidebarTaskItem: Identifiable, Equatable {
    /// Stable identity for sidebar animations, assigned by
    /// `AppState.updateTasks`: unlike `range.location` it survives the
    /// shifts that edits above the task cause, so cards are not
    /// removed/reinserted (and re-animated) on every keystroke.
    var uid: Int
    let text: String
    let done: Bool
    /// Raw "yyyy-MM-dd" from the document, nil for tasks created before
    /// dates were tracked.
    let created: String?
    /// Titles of the headings above the task; nil when the task sits
    /// outside that heading level (or the heading is empty).
    let h1: String?
    let h2: String?
    let range: NSRange

    var id: Int { uid }

    static func == (lhs: SidebarTaskItem, rhs: SidebarTaskItem) -> Bool {
        lhs.uid == rhs.uid && lhs.text == rhs.text && lhs.done == rhs.done
            && lhs.created == rhs.created && lhs.h1 == rhs.h1 && lhs.h2 == rhs.h2
            && lhs.range == rhs.range
    }
}

/// Sidebar tabs, in display order. Switchable via the arrows next to the
/// tab title, the hover list, and two-finger swipe gestures.
enum SidebarTab: Int, CaseIterable, Identifiable {
    case structure, tasks, deadlines, routine, photos, files, control

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .structure: return "Структура"
        case .tasks: return "Задания"
        case .deadlines: return "Дедлайны"
        case .routine: return "Рутина"
        case .photos: return "Фотографии"
        case .files: return "Файлы"
        case .control: return "Управление"
        }
    }
}

final class AppState: ObservableObject {
    @Published var outline: [OutlineItem] = []
    /// Active tasks first (newest on top), then done tasks (also newest
    /// on top) — the tab renders them in this exact order.
    @Published var tasks: [SidebarTaskItem] = []
    /// Source of fresh task identities; see `updateTasks`.
    private var nextTaskUID = 0
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var matches: [NSRange] = []
    @Published var currentMatchIndex = 0
    @Published var findFocusRequest = 0
    @Published var sidebarTab: SidebarTab = .structure
    /// Paragraph start of the task currently being typed in the editor, if
    /// any. While set, that card wiggles and shows a typing placeholder
    /// instead of live text; cleared at the debounced refresh.
    @Published var editingTaskLocation: Int?

    @Published var bodyPointSize: Double = {
        let saved = UserDefaults.standard.object(forKey: "bodyPointSize") as? Double
        return saved ?? OBFTheme.defaultBodySize
    }() {
        didSet {
            let clamped = min(OBFTheme.maxBodySize, max(OBFTheme.minBodySize, bodyPointSize))
            if clamped != bodyPointSize {
                bodyPointSize = clamped
            }
            UserDefaults.standard.set(bodyPointSize, forKey: "bodyPointSize")
        }
    }

    let store: DocumentStore
    weak var editor: EditorCoordinating?

    init(store: DocumentStore = DocumentStore()) {
        self.store = store
    }

    var matchCounterText: String {
        matches.isEmpty ? "0/0" : "\(currentMatchIndex + 1)/\(matches.count)"
    }

    var bodyFont: NSFont { OBFTheme.font(size: bodyPointSize, bold: false) }
    var h2Font: NSFont { OBFTheme.font(size: bodyPointSize + 4, bold: true) }
    var h1Font: NSFont { OBFTheme.font(size: bodyPointSize + 10, bold: true) }

    func selectNextSidebarTab() {
        moveSidebarTab(by: 1)
    }

    func selectPrevSidebarTab() {
        moveSidebarTab(by: -1)
    }

    private func moveSidebarTab(by delta: Int) {
        let count = SidebarTab.allCases.count
        let raw = (sidebarTab.rawValue + delta + count) % count
        sidebarTab = SidebarTab(rawValue: raw) ?? .structure
    }

    func showFindBar() {
        findVisible = true
        findFocusRequest += 1
        // Opening search drops any text selection made before it, so the
        // only highlight on screen is the current match.
        editor?.clearSelection()
        editor?.updateFindMatches()
    }

    func closeFind() {
        findVisible = false
        editor?.clearFindHighlight()
        editor?.clearSelection()
        editor?.focusEditor()
    }

    /// Replaces the sidebar task list, keeping card identities stable
    /// across rebuilds: a task keeps its uid while only its position,
    /// state or text changes, so SwiftUI animates cards appearing, moving
    /// between the active/done sections and disappearing — instead of
    /// re-creating every card whose range shifted after an edit above it
    /// (edits shift the ranges of all tasks below them).
    func updateTasks(_ incoming: [SidebarTaskItem]) {
        var unused = tasks
        var result: [SidebarTaskItem] = []
        result.reserveCapacity(incoming.count)

        func take(where predicate: (SidebarTaskItem) -> Bool) -> Int? {
            guard let index = unused.firstIndex(where: predicate) else { return nil }
            return unused.remove(at: index).uid
        }

        for var task in incoming {
            var uid: Int? = nil
            if task.range.location == editingTaskLocation {
                // The task being typed keeps its identity even though its
                // text changes under the caret.
                uid = take(where: { $0.range.location == task.range.location })
            }
            if uid == nil {
                uid = take(where: {
                        $0.text == task.text && $0.done == task.done
                            && $0.created == task.created && $0.h1 == task.h1 && $0.h2 == task.h2
                    })
                    ?? take(where: {
                        // Done-toggle: same text and metadata, flipped state.
                        $0.text == task.text
                            && $0.created == task.created && $0.h1 == task.h1 && $0.h2 == task.h2
                    })
            }
            if uid == nil {
                // Text edit: same metadata, rewritten text. Trusted only
                // when the match is unique on both sides — otherwise a
                // deletion could steal a sibling card's identity.
                let meta: (SidebarTaskItem) -> Bool = {
                    $0.done == task.done && $0.created == task.created
                        && $0.h1 == task.h1 && $0.h2 == task.h2
                }
                if incoming.filter(meta).count == 1, unused.filter(meta).count == 1 {
                    uid = take(where: meta)
                }
            }
            task.uid = uid ?? freshTaskUID()
            result.append(task)
        }

        guard result != tasks else { return }
        tasks = result
    }

    private func freshTaskUID() -> Int {
        nextTaskUID += 1
        return nextTaskUID
    }
}
