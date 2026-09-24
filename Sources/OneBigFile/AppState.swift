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
    @Published var sidebarTab: SidebarTab = .structure {
        didSet {
            if sidebarTab != .routine {
                selectedRoutineItemIDs = []
            }
        }
    }
    /// Paragraph start of the task currently being typed in the editor, if
    /// any. While set, that card wiggles and shows a typing placeholder
    /// instead of live text; cleared at the debounced refresh.
    @Published var editingTaskLocation: Int?
    /// The one task card whose full text is currently expanded; expanding
    /// another card collapses this one. Lives in AppState (not in view
    /// state) so it survives sidebar rebuilds and can be driven by tests.
    @Published var expandedTaskID: Int?
    /// The task shown full-size in the task modal (by uid), if any. The
    /// modal reads the task live from `tasks`, so it always shows current
    /// text and location.
    @Published var modalTaskID: Int?

    var modalTask: SidebarTaskItem? {
        modalTaskID.flatMap { id in tasks.first { $0.id == id } }
    }

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

    // MARK: Routine state

    let routineStore: RoutineStore
    @Published private(set) var routine: RoutineData
    /// Weekday shown in the routine tab, 0 = Monday.
    @Published private(set) var routineDay: Int
    /// Whether the last day switch moved forward through the week; drives
    /// the slide direction of the day content.
    @Published private(set) var routineDayForward = true
    /// Today's weekday (0 = Monday) and date key, refreshed at midnight.
    @Published private(set) var routineToday: Int
    @Published private(set) var todayKey: String
    /// Selected cards of the shown day (click selects one, Shift+click
    /// adds or removes).
    @Published var selectedRoutineItemIDs: Set<UUID> = []
    @Published var routineEditor: RoutineEditorRequest?
    /// True after a routine card was clicked: Delete and Cmd+Z act on the
    /// routine until the user clicks back into the text.
    private(set) var routineKeyFocus = false
    /// Removals, most recent last; cleared when focus returns to the text.
    private(set) var routineUndoStack: [RoutineDeletion] = []
    /// Set by Cmd+T: until this moment a digit 1…7 picks the weekday.
    var routineChordDeadline: Date?

    var anyModalOpen: Bool { modalTaskID != nil || routineEditor != nil }

    init(store: DocumentStore = DocumentStore(), routineStore: RoutineStore? = nil) {
        self.store = store
        let routineStore = routineStore ?? RoutineStore(
            fileURL: store.fileURL.deletingLastPathComponent().appendingPathComponent("routine.json"))
        self.routineStore = routineStore
        routine = routineStore.load()
        let today = Self.currentDay()
        routineToday = today.weekday
        todayKey = today.key
        routineDay = today.weekday
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

    // MARK: - Routine

    /// Weekday (0 = Monday) and "yyyy-MM-dd" key of `date`.
    static func currentDay(_ date: Date = Date()) -> (weekday: Int, key: String) {
        (RoutineDate.weekday(date), RoutineDate.key(date))
    }

    /// Re-reads the date; at midnight the tab moves on to the new day if
    /// it was showing today, and done marks of yesterday stop counting.
    func refreshToday(_ date: Date = Date()) {
        let today = Self.currentDay(date)
        guard today.key != todayKey else { return }
        let wasShowingToday = (pendingRoutineDay ?? routineDay) == routineToday
        todayKey = today.key
        routineToday = today.weekday
        if wasShowingToday {
            selectRoutineDay(today.weekday)
        }
    }

    func isRoutineItemDone(_ task: RoutineTask) -> Bool {
        task.isDone(on: todayKey)
    }

    /// Shows the routine tab on `day`, or on today when nil (Cmd+R /
    /// Cmd+T chord).
    func showRoutine(day: Int?) {
        routineChordDeadline = nil
        sidebarTab = .routine
        selectRoutineDay(day ?? routineToday)
    }

    /// Switches the shown weekday. `forward` overrides the slide direction
    /// (the neighbours of Monday and Sunday wrap around the week).
    func selectRoutineDay(_ day: Int, forward: Bool? = nil) {
        let current = pendingRoutineDay ?? routineDay
        guard (0..<7).contains(day), day != current else { return }
        let direction = forward ?? (day > current)
        selectedRoutineItemIDs = []
        routineDayGeneration += 1
        if direction == routineDayForward, pendingRoutineDay == nil {
            routineDay = day
        } else {
            // The outgoing day view keeps the transition it was rendered
            // with, so the direction must land one update before the day.
            // Only the latest of several quick switches is applied.
            routineDayForward = direction
            pendingRoutineDay = day
            let generation = routineDayGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.routineDayGeneration else { return }
                self.pendingRoutineDay = nil
                self.routineDay = day
            }
        }
    }

    /// Day switch waiting for its deferred apply, see `selectRoutineDay`.
    private var pendingRoutineDay: Int?
    private var routineDayGeneration = 0

    /// Selects exactly this card (or adds it, `extend`) and takes the
    /// keys away from the text.
    func selectRoutineItem(_ id: UUID, extend: Bool = false) {
        if extend {
            selectedRoutineItemIDs.insert(id)
        } else {
            selectedRoutineItemIDs = [id]
        }
        routineKeyFocus = true
        // Keys must not reach the text view while a card is selected.
        if let window = NSApp.keyWindow, window.firstResponder is NSText {
            window.makeFirstResponder(nil)
        }
    }

    /// Click on a card. Plain click selects just this card, or clears the
    /// selection when it was the only selected one. Shift+click adds the
    /// card to the selection or takes it out. The second click of a double
    /// click selects the card and opens its editor.
    func clickRoutineItem(_ id: UUID, day: Int, clickCount: Int, shift: Bool = false) {
        if clickCount >= 2 {
            selectRoutineItem(id)
            routineEditor = RoutineEditorRequest(day: day, itemID: id)
        } else if shift {
            if selectedRoutineItemIDs.contains(id) {
                selectedRoutineItemIDs.remove(id)
            } else {
                selectRoutineItem(id, extend: true)
            }
        } else if selectedRoutineItemIDs == [id] {
            selectedRoutineItemIDs = []
        } else {
            selectRoutineItem(id)
        }
    }

    func endRoutineKeyFocus() {
        routineKeyFocus = false
        routineUndoStack.removeAll()
        selectedRoutineItemIDs = []
    }

    func routineTask(_ id: UUID) -> RoutineTask? {
        routine.task(id)
    }

    /// Date key of weekday `day` in the current week (the routine tab
    /// shows the week that contains today).
    func routineDate(for day: Int) -> String {
        RoutineDate.adding(day - routineToday, to: todayKey)
    }

    /// Whether the task is on in the current week's `day` (false for an
    /// every-other-week task in its off week).
    func isRoutineItemActive(_ task: RoutineTask, day: Int) -> Bool {
        task.isActiveWeek(routineDate(for: day))
    }

    /// The plan the editor produces: `days` every `everyWeeks` weeks, the
    /// first week `startOffset` weeks from this one (0 = this week).
    func routinePlan(days: Set<Int>, everyWeeks: Int, startOffset: Int) -> RoutineScheduleEntry {
        let every = max(1, everyWeeks)
        return RoutineScheduleEntry(
            from: todayKey, days: days, everyWeeks: every,
            anchor: every > 1
                ? RoutineDate.adding(7 * max(0, startOffset), to: RoutineDate.weekStart(todayKey))
                : nil)
    }

    /// Creates one task repeating on `days`, every `everyWeeks` weeks from
    /// the week `startOffset` weeks ahead.
    func addRoutineItem(_ text: String, days: [Int], everyWeeks: Int = 1, startOffset: Int = 0) {
        let text = Self.cleanRoutineText(text)
        let days = Set(days.filter { (0..<7).contains($0) })
        guard !text.isEmpty, !days.isEmpty else { return }
        let task = RoutineTask(
            text: text, created: todayKey,
            schedule: [routinePlan(days: days, everyWeeks: everyWeeks, startOffset: startOffset)])
        routine.tasks.append(task)
        for day in days.sorted() {
            routine.order[day].append(task.id)
        }
        routineStore.save(routine)
    }

    /// Items of `day` in display order: the ones still to do, then the
    /// ones done today, then the ones in their off week — each group
    /// keeping its stored order.
    func routineItemsForDisplay(day: Int) -> [RoutineTask] {
        let tasks = routine.tasks(on: day)
        let on = tasks.filter { isRoutineItemActive($0, day: day) }
        let off = tasks.filter { !isRoutineItemActive($0, day: day) }
        return on.filter { !isRoutineItemDone($0) } + on.filter(isRoutineItemDone) + off
    }

    /// Edit modal: new text (shared by all days of the task) and new days.
    /// Days taken away drop the task from those days' lists; days added
    /// put it at the bottom of theirs.
    func updateRoutineItem(_ id: UUID, text: String, days: Set<Int>,
                           everyWeeks: Int = 1, startOffset: Int = 0) {
        let text = Self.cleanRoutineText(text)
        guard !text.isEmpty, !days.isEmpty, let index = routine.taskIndex(id),
              !routine.tasks[index].isDeleted else { return }
        routine.tasks[index].text = text
        routine.tasks[index].setPlan(
            routinePlan(days: days, everyWeeks: everyWeeks, startOffset: startOffset), from: todayKey)
        routine.normalizeOrder()
        routineStore.save(routine)
    }

    /// Drag and drop: `activeOrder` is the new order of the day's cards
    /// that are not done today. Done cards keep their stored slots, so they
    /// return to their places once the marks reset.
    func reorderRoutineItems(day: Int, activeOrder: [UUID]) {
        guard (0..<7).contains(day) else { return }
        let moved = Set(activeOrder)
        guard moved.isSubset(of: routine.order[day]) else { return }
        var queue = activeOrder[...]
        let reordered = routine.order[day].map { moved.contains($0) ? queue.removeFirst() : $0 }
        guard reordered != routine.order[day] else { return }
        routine.order[day] = reordered
        routineStore.save(routine)
    }

    /// Toggles today's done mark.
    func toggleRoutineDone(_ id: UUID) {
        guard let index = routine.taskIndex(id) else { return }
        if let doneIndex = routine.tasks[index].done.firstIndex(of: todayKey) {
            routine.tasks[index].done.remove(at: doneIndex)
        } else {
            routine.tasks[index].done.append(todayKey)
            routine.tasks[index].done.sort()
        }
        routineStore.save(routine)
    }

    /// Delete: takes the selected cards off the shown day only. A task
    /// that loses its last day is archived. One Cmd+Z brings them all back.
    func deleteSelectedRoutineItems() {
        let day = pendingRoutineDay ?? routineDay
        let ids = routine.order[day].filter(selectedRoutineItemIDs.contains)
        guard !ids.isEmpty else { return }
        recordDeletion(of: ids, day: day)
        for id in ids {
            guard let index = routine.taskIndex(id) else { continue }
            var days = routine.tasks[index].currentDays
            days.remove(day)
            if days.isEmpty {
                routine.tasks[index].deleted = todayKey
            } else {
                routine.tasks[index].setDays(days, from: todayKey)
            }
        }
        selectedRoutineItemIDs = []
        routine.normalizeOrder()
        routineStore.save(routine)
    }

    /// "Удалить из всех дней": archives the task (its history stays in
    /// routine.json for statistics). Undoable with Cmd+Z like Delete.
    func deleteRoutineTaskEverywhere(_ id: UUID, day: Int) {
        guard let index = routine.taskIndex(id), !routine.tasks[index].isDeleted else { return }
        recordDeletion(of: [id], day: day)
        routine.tasks[index].deleted = todayKey
        selectedRoutineItemIDs.remove(id)
        routine.normalizeOrder()
        routineStore.save(routine)
        // Keys stay with the routine so Cmd+Z works right after the modal.
        routineKeyFocus = true
    }

    private func recordDeletion(of ids: [UUID], day: Int) {
        var positions: [UUID: [Int: Int]] = [:]
        for id in ids {
            for weekday in 0..<7 {
                if let index = routine.order[weekday].firstIndex(of: id) {
                    positions[id, default: [:]][weekday] = index
                }
            }
        }
        routineUndoStack.append(RoutineDeletion(
            tasksBefore: ids.compactMap(routine.task), positions: positions, day: day))
    }

    /// Cmd+Z: restores the tasks of the last removal exactly as they were
    /// (text, schedule, place in every day's list), shows the day it
    /// happened on and selects them again.
    @discardableResult
    func undoRoutineDeletion() -> Bool {
        guard let deletion = routineUndoStack.popLast() else { return false }
        for before in deletion.tasksBefore {
            guard let index = routine.taskIndex(before.id) else { continue }
            // Done marks made meanwhile are kept.
            var restored = before
            restored.done = routine.tasks[index].done
            routine.tasks[index] = restored
            for day in 0..<7 {
                routine.order[day].removeAll { $0 == before.id }
            }
        }
        // Reinsert by ascending original index so earlier slots are filled
        // first and later indices stay correct.
        for day in 0..<7 {
            let entries = deletion.positions
                .compactMap { id, places in places[day].map { (id, $0) } }
                .sorted { $0.1 < $1.1 }
            for (id, index) in entries {
                routine.order[day].insert(id, at: min(index, routine.order[day].count))
            }
        }
        routine.normalizeOrder()
        routineStore.save(routine)
        sidebarTab = .routine
        selectRoutineDay(deletion.day)
        selectedRoutineItemIDs = Set(deletion.tasksBefore.map(\.id))
            .filter { routine.order[deletion.day].contains($0) }
        return true
    }

    private static func cleanRoutineText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
