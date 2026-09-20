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
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var matches: [NSRange] = []
    @Published var currentMatchIndex = 0
    @Published var findFocusRequest = 0
    @Published var sidebarTab: SidebarTab = .structure

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
}
