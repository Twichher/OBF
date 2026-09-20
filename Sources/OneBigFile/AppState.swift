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

final class AppState: ObservableObject {
    @Published var outline: [OutlineItem] = []
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var matches: [NSRange] = []
    @Published var currentMatchIndex = 0
    @Published var findFocusRequest = 0

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

    let store = DocumentStore()
    weak var editor: EditorCoordinating?

    var matchCounterText: String {
        matches.isEmpty ? "0/0" : "\(currentMatchIndex + 1)/\(matches.count)"
    }

    var bodyFont: NSFont { OBFTheme.font(size: bodyPointSize, bold: false) }
    var h2Font: NSFont { OBFTheme.font(size: bodyPointSize + 4, bold: true) }
    var h1Font: NSFont { OBFTheme.font(size: bodyPointSize + 10, bold: true) }

    func showFindBar() {
        findVisible = true
        findFocusRequest += 1
        editor?.updateFindMatches()
    }

    func closeFind() {
        findVisible = false
        editor?.clearFindHighlight()
        editor?.focusEditor()
    }
}
