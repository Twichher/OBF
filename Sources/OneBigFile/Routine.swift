import AppKit

/// Weekday helpers; days are 0 = Monday … 6 = Sunday throughout.
enum Weekday {
    static let names = [
        "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"
    ]
    static let shortNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    /// Day names in routine.json schedules.
    static let keys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    /// Day names of the `order` object in routine.json.
    static let orderKeys = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    /// "Каждый день", or the short names of the days: "Вт · Чт · Сб".
    static func summary(_ days: Set<Int>) -> String {
        days.count == 7 ? "Каждый день" : days.sorted().map { shortNames[$0] }.joined(separator: " · ")
    }

    /// "через неделю", "раз в 3 недели", "раз в 5 недель"; nil for weekly.
    static func interval(_ everyWeeks: Int) -> String? {
        switch everyWeeks {
        case ...1: return nil
        case 2: return "через неделю"
        default:
            let mod10 = everyWeeks % 10, mod100 = everyWeeks % 100
            let word: String
            if mod10 == 1 && mod100 != 11 {
                word = "неделю"
            } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
                word = "недели"
            } else {
                word = "недель"
            }
            return "раз в \(everyWeeks) \(word)"
        }
    }
}

/// Date keys ("yyyy-MM-dd") used throughout the routine. Keys compare
/// correctly as plain strings.
enum RoutineDate {
    private static let calendar = Calendar(identifier: .gregorian)

    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Noon of that day, so adding days never trips over DST changes.
    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let date = date(key),
              let moved = calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return Self.key(moved)
    }

    /// 0 = Monday … 6 = Sunday.
    static func weekday(_ date: Date) -> Int {
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func weekday(_ key: String) -> Int {
        date(key).map(weekday) ?? 0
    }

    /// Monday of the week `key` falls in.
    static func weekStart(_ key: String) -> String {
        adding(-weekday(key), to: key)
    }

    /// Whole weeks from the week of `a` to the week of `b` (negative when
    /// `b` is earlier).
    static func weeksBetween(_ a: String, _ b: String) -> Int {
        guard let start = date(weekStart(a)), let end = date(weekStart(b)) else { return 0 }
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return Int((Double(days) / 7).rounded())
    }

    /// "24.09", "1.10".
    static func short(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]) else { return key }
        return "\(day).\(parts[1])"
    }
}

/// How many times in a row a task was done, counted back from today (today
/// itself only once it is marked; until then yesterday's streak holds).
enum RoutineStreak: Equatable {
    /// Every-day task: consecutive days.
    case daily(Int)
    /// Other tasks: per weekday, consecutive weeks that day was done
    /// ("ВТ-3" = the last three Tuesdays).
    case weekly([(day: Int, count: Int)])

    var isEmpty: Bool {
        switch self {
        case .daily(let count): return count == 0
        case .weekly(let days): return days.allSatisfy { $0.count == 0 }
        }
    }

    static func == (lhs: RoutineStreak, rhs: RoutineStreak) -> Bool {
        switch (lhs, rhs) {
        case let (.daily(a), .daily(b)): return a == b
        case let (.weekly(a), .weekly(b)): return a.map(\.day) == b.map(\.day) && a.map(\.count) == b.map(\.count)
        default: return false
        }
    }
}

/// One period of a task's schedule: from `from` ("yyyy-MM-dd") on, the
/// task repeats on `days` — every `everyWeeks` weeks counted from the week
/// of `anchor` — until the next entry takes over.
struct RoutineScheduleEntry: Equatable {
    var from: String
    var days: Set<Int>
    /// 1 = every week, 2 = every other week, …
    var everyWeeks = 1
    /// Monday of a week the task is on (and the first such week); only
    /// used when `everyWeeks` > 1.
    var anchor: String?

    /// Whether the week of `date` is one the task is on.
    func isActiveWeek(_ date: String) -> Bool {
        guard everyWeeks > 1, let anchor else { return true }
        let weeks = RoutineDate.weeksBetween(anchor, date)
        return weeks >= 0 && weeks % everyWeeks == 0
    }

    /// Same plan (days and repetition), ignoring when it started.
    func samePlan(as other: RoutineScheduleEntry) -> Bool {
        days == other.days && everyWeeks == other.everyWeeks
            && (everyWeeks == 1 || anchor == other.anchor)
    }
}

extension RoutineScheduleEntry: Codable {
    private enum CodingKeys: String, CodingKey { case from, days, everyWeeks, anchor }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(String.self, forKey: .from)
        let keys = try container.decode([String].self, forKey: .days)
        days = Set(keys.compactMap { Weekday.keys.firstIndex(of: $0) })
        everyWeeks = max(1, try container.decodeIfPresent(Int.self, forKey: .everyWeeks) ?? 1)
        anchor = try container.decodeIfPresent(String.self, forKey: .anchor)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(days.sorted().map { Weekday.keys[$0] }, forKey: .days)
        // Weekly entries keep the old, shorter form.
        if everyWeeks > 1 {
            try container.encode(everyWeeks, forKey: .everyWeeks)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        }
    }
}

/// A routine task. One task may repeat on several weekdays; its schedule
/// history and the log of done dates are kept for statistics, and a task
/// removed from all days stays in the file as an archive (`deleted`).
struct RoutineTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// "yyyy-MM-dd" of creation.
    var created: String
    /// "yyyy-MM-dd" of removal from all days; nil while the task is live.
    var deleted: String?
    /// Oldest first; the last entry is the current schedule.
    var schedule: [RoutineScheduleEntry]
    /// Dates ("yyyy-MM-dd") the task was marked done, ascending.
    var done: [String] = []

    var isDeleted: Bool { deleted != nil }

    /// Weekdays the task currently repeats on (empty once deleted).
    var currentDays: Set<Int> {
        isDeleted ? [] : (schedule.last?.days ?? [])
    }

    func isDone(on date: String) -> Bool {
        done.contains(date)
    }

    /// Whether the task was due on `date` by the schedule in force then
    /// (and it existed then).
    func isScheduled(on date: String) -> Bool {
        guard let entry = entry(on: date) else { return false }
        return entry.days.contains(RoutineDate.weekday(date)) && entry.isActiveWeek(date)
    }

    /// The weekday of `date` is in the plan, but its week is skipped (an
    /// every-other-week task in its off week). Such dates are neither due
    /// nor missed.
    func isOffWeek(on date: String) -> Bool {
        guard let entry = entry(on: date) else { return false }
        return entry.days.contains(RoutineDate.weekday(date)) && !entry.isActiveWeek(date)
    }

    /// The schedule in force on `date`, while the task existed.
    private func entry(on date: String) -> RoutineScheduleEntry? {
        guard date >= created, deleted.map({ date < $0 }) ?? true else { return nil }
        return schedule.last { $0.from <= date }
    }

    /// Current repetition (1 = every week).
    var everyWeeks: Int { schedule.last?.everyWeeks ?? 1 }

    /// By the current plan: is the week of `date` one the task is on?
    func isActiveWeek(_ date: String) -> Bool {
        schedule.last?.isActiveWeek(date) ?? true
    }

    /// The first due date after `date` by the current plan.
    func nextDueDate(after date: String) -> String? {
        guard let plan = schedule.last, !plan.days.isEmpty, !isDeleted else { return nil }
        var day = RoutineDate.adding(1, to: date)
        for _ in 0..<(7 * max(1, plan.everyWeeks) * 2 + 7) {
            if plan.days.contains(RoutineDate.weekday(day)) && plan.isActiveWeek(day) {
                return day
            }
            day = RoutineDate.adding(1, to: day)
        }
        return nil
    }

    /// Streak as of `today`: one daily count for an every-day task, else a
    /// count per current weekday. A due date left undone ends the streak;
    /// a date that was not due is skipped (daily) or ends it (weekly — that
    /// weekday was not part of the routine then).
    func streak(today: String) -> RoutineStreak {
        let days = currentDays
        if days.count == 7 {
            var date = isDone(on: today) ? today : RoutineDate.adding(-1, to: today)
            var count = 0
            while date >= created {
                if isScheduled(on: date) {
                    guard isDone(on: date) else { break }
                    count += 1
                }
                date = RoutineDate.adding(-1, to: date)
            }
            return .daily(count)
        }
        let todayWeekday = RoutineDate.weekday(today)
        return .weekly(days.sorted().map { day in
            // Latest occurrence of this weekday up to today.
            var date = RoutineDate.adding(-((todayWeekday - day + 7) % 7), to: today)
            if date == today && !isDone(on: today) {
                date = RoutineDate.adding(-7, to: date)
            }
            var count = 0
            while date >= created {
                if isScheduled(on: date) {
                    guard isDone(on: date) else { break }
                    count += 1
                } else if !isOffWeek(on: date) {
                    // The weekday was not in the plan then.
                    break
                }
                date = RoutineDate.adding(-7, to: date)
            }
            return (day, count)
        })
    }

    /// Records new days (keeping the repetition) from `date` on.
    mutating func setDays(_ days: Set<Int>, from date: String) {
        var plan = schedule.last ?? RoutineScheduleEntry(from: date, days: days)
        plan.days = days
        setPlan(plan, from: date)
    }

    /// Records a new plan from `date` on. Several changes within one day
    /// collapse into a single entry, and an entry equal to the one before
    /// it is dropped, so the history holds real periods only.
    mutating func setPlan(_ plan: RoutineScheduleEntry, from date: String) {
        var plan = plan
        plan.from = date
        if plan.everyWeeks <= 1 {
            plan.everyWeeks = 1
            plan.anchor = nil
        }
        if let last = schedule.last, last.from == date {
            schedule.removeLast()
        }
        if !(schedule.last.map { $0.samePlan(as: plan) } ?? false) {
            schedule.append(plan)
        }
    }
}

/// Everything in routine.json: all tasks (live and archived) and the card
/// order of every weekday.
struct RoutineData: Equatable {
    static let version = 2

    var tasks: [RoutineTask] = []
    /// Per weekday, the ids of the live tasks scheduled on it, in display
    /// order.
    var order: [[UUID]] = Array(repeating: [], count: 7)

    func task(_ id: UUID) -> RoutineTask? {
        tasks.first { $0.id == id }
    }

    func taskIndex(_ id: UUID) -> Int? {
        tasks.firstIndex { $0.id == id }
    }

    /// Live tasks of `day` in stored order.
    func tasks(on day: Int) -> [RoutineTask] {
        guard (0..<7).contains(day) else { return [] }
        return order[day].compactMap { task($0) }
    }

    /// Makes `order` match the schedules: drops ids of tasks that are gone
    /// or no longer on that day, appends scheduled tasks that are missing.
    mutating func normalizeOrder() {
        for day in 0..<7 {
            var seen = Set<UUID>()
            order[day] = order[day].filter { id in
                guard let task = task(id), task.currentDays.contains(day) else { return false }
                return seen.insert(id).inserted
            }
            for task in tasks where task.currentDays.contains(day) && !seen.contains(task.id) {
                order[day].append(task.id)
            }
        }
    }
}

extension RoutineData: Codable {
    private enum CodingKeys: String, CodingKey { case version, tasks, order }

    private struct DayKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    struct UnsupportedVersion: Error {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decodeIfPresent(Int.self, forKey: .version) == Self.version else {
            throw UnsupportedVersion()
        }
        tasks = try container.decode([RoutineTask].self, forKey: .tasks)
        let orderContainer = try container.nestedContainer(keyedBy: DayKey.self, forKey: .order)
        order = try Weekday.orderKeys.map {
            try orderContainer.decodeIfPresent([UUID].self, forKey: DayKey(stringValue: $0)) ?? []
        }
        normalizeOrder()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(tasks, forKey: .tasks)
        var orderContainer = container.nestedContainer(keyedBy: DayKey.self, forKey: .order)
        for (key, ids) in zip(Weekday.orderKeys, order) {
            try orderContainer.encode(ids, forKey: DayKey(stringValue: key))
        }
    }
}

/// Persists the routine as routine.json next to the document.
final class RoutineStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> RoutineData {
        guard let data = try? Data(contentsOf: fileURL) else { return RoutineData() }
        do {
            return try JSONDecoder().decode(RoutineData.self, from: data)
        } catch is RoutineData.UnsupportedVersion {
            // A routine from before the task model (per-day copies) is not
            // carried over: it is set aside as routine.v1.json and the
            // routine starts empty.
            moveAside(to: fileURL.deletingPathExtension().appendingPathExtension("v1.json"))
        } catch {
            // Unreadable file: keep a copy instead of overwriting it on the
            // next save.
            moveAside(to: fileURL.appendingPathExtension("bak"))
        }
        return RoutineData()
    }

    func save(_ data: RoutineData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let json = try? encoder.encode(data) else { return }
        try? json.write(to: fileURL, options: .atomic)
    }

    private func moveAside(to backup: URL) {
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

/// Add / edit request shown in the routine modal.
struct RoutineEditorRequest: Identifiable, Equatable {
    /// The day the modal was opened from.
    let day: Int
    /// nil = new task.
    let itemID: UUID?
    var id: String { "\(day)-\(itemID?.uuidString ?? "new")" }
}

/// One undoable removal (Delete from a day for one or several cards, or
/// "Удалить из всех дней"): the affected tasks as they were, and where
/// each stood in every day's order.
struct RoutineDeletion: Equatable {
    let tasksBefore: [RoutineTask]
    /// Task id -> weekday -> index in that day's order.
    let positions: [UUID: [Int: Int]]
    /// The day to show after Cmd+Z.
    let day: Int
}

/// App-wide keyboard handling of the routine:
/// - Cmd+R opens the routine tab on today.
/// - Cmd+T followed by 1…7 (with or without Cmd still held) opens
///   Monday…Sunday; Cmd+T alone changes nothing.
/// - While a routine card is selected (keyboard focus left the editor),
///   Delete removes it and Cmd+Z brings deleted items back.
/// Physical key codes are used so the shortcuts work in any layout.
enum RoutineKeys {
    /// How long after Cmd+T a digit still selects a day.
    static let chordWindow: TimeInterval = 1.5

    static let keyR: UInt16 = 15
    static let keyT: UInt16 = 17
    static let keyZ: UInt16 = 6
    static let keyBackspace: UInt16 = 51
    static let keyForwardDelete: UInt16 = 117
    /// Digits 1…7 on the main keyboard row.
    static let dayKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26]

    private static var keyMonitor: Any?
    private static var mouseMonitor: Any?

    static func install(appState: AppState) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appState] event in
            guard let appState else { return event }
            return handle(event, appState: appState) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak appState] event in
            guard let appState, !appState.anyModalOpen, event.window?.attachedSheet == nil else { return event }
            // A click outside the sidebar (into the text) ends routine
            // keyboard mode: selection and undo history are dropped.
            if event.window != nil, !sidebarFrame.contains(event.locationInWindow) {
                appState.endRoutineKeyFocus()
            }
            return event
        }
    }

    /// The sidebar in window coordinates; the window layout is fixed (see
    /// OBFTheme).
    static var sidebarFrame: CGRect {
        CGRect(
            x: OBFTheme.windowWidth - OBFTheme.contentPadding - OBFTheme.sidebarWidth,
            y: OBFTheme.contentPadding,
            width: OBFTheme.sidebarWidth,
            height: OBFTheme.windowHeight - OBFTheme.contentPadding * 2
        )
    }

    /// Returns true when the event was consumed.
    static func handle(_ event: NSEvent, appState: AppState, now: Date = Date()) -> Bool {
        guard !appState.anyModalOpen else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Second half of the Cmd+T chord.
        if let deadline = appState.routineChordDeadline {
            appState.routineChordDeadline = nil
            if now <= deadline, flags.subtracting(.command).isEmpty,
               let day = dayKeyCodes.firstIndex(of: event.keyCode) {
                appState.showRoutine(day: day)
                return true
            }
        }

        if flags == [.command], event.keyCode == keyR {
            appState.showRoutine(day: nil)
            return true
        }
        if flags == [.command], event.keyCode == keyT {
            appState.routineChordDeadline = now.addingTimeInterval(chordWindow)
            return true
        }

        guard appState.routineKeyFocus else { return false }
        if let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder,
           responder is NSText {
            // Typing went back to the text (or the find field).
            appState.endRoutineKeyFocus()
            return false
        }

        if event.keyCode == keyZ, flags.contains(.command) {
            // Swallowed even when there is nothing to restore: the text's
            // undo history must not run while the routine has the keys.
            if flags == [.command] {
                appState.undoRoutineDeletion()
            }
            return true
        }
        if event.keyCode == keyBackspace || event.keyCode == keyForwardDelete,
           flags.isEmpty, appState.sidebarTab == .routine,
           !appState.selectedRoutineItemIDs.isEmpty {
            appState.deleteSelectedRoutineItems()
            return true
        }
        return false
    }
}
