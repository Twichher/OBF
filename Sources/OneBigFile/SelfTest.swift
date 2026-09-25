import AppKit

/// Headless reproduction of user keystroke sequences. Run the app binary with
/// `--selftest`; prints the state of typing attributes and paragraph markers
/// after every step so style leaks can be traced to the exact operation.
enum SelfTest {

    static func run() -> Int32 {
        var failures = 0

        print("== A: heading, Enter, type, Enter, Backspace, type ==")
        if !scenarioA() { failures += 1 }

        print("== B: user repro — heading, Enter, Enter, Backspace, type (empty line) ==")
        if !scenarioB() { failures += 1 }

        print("== C: Cmd+1 on empty line under a heading ==")
        if !scenarioC() { failures += 1 }

        print("== D: find cycles through matches with Enter (wraps around) ==")
        if !scenarioD() { failures += 1 }

        print("== E: highlight stays off after closing find and refreshing ==")
        if !scenarioE() { failures += 1 }

        print("== F: long line wraps within the text view width ==")
        if !scenarioF() { failures += 1 }

        print("== G: typing over a selection (crash repro, issue #4-style) ==")
        if !scenarioG() { failures += 1 }

        print("== H: find clears selection; highlight survives edits/zoom; close clears all ==")
        if !scenarioH() { failures += 1 }

        print("== I: two-finger swipe recognizer (left=next, right=prev, once per gesture) ==")
        if !scenarioI() { failures += 1 }

        print("== J: Cmd+3 creates a task, typing follows, Enter ends it, markdown round-trip ==")
        if !scenarioJ() { failures += 1 }

        print("== K: Cmd+4 toggles done (dimmed text, - [x]) ==")
        if !scenarioK() { failures += 1 }

        print("== L: Backspace right after the checkbox un-tasks the line, keeps text ==")
        if !scenarioL() { failures += 1 }

        print("== M: markdown parse/serialize round-trip with tasks ==")
        if !scenarioM() { failures += 1 }

        print("== N: task text wraps with hanging indent aligned after the checkbox ==")
        if !scenarioN() { failures += 1 }

        print("== O: sidebar task list — dates, order, location paths, round-trip ==")
        if !scenarioO() { failures += 1 }

        print("== P: sidebar task uids survive edits above and done-toggle ==")
        if !scenarioP() { failures += 1 }

        print("== Q: expanded task text height is capped (scrolls past 8 lines) ==")
        if !scenarioQ() { failures += 1 }

        print("== R: Enter from a task clears the typing mark; only the new task is marked ==")
        if !scenarioR() { failures += 1 }

        print("== S: expanded task text eats scroll events at its edges ==")
        if !scenarioS() { failures += 1 }

        print("== T: short task texts (<= 2 lines) get no expand chevron ==")
        if !scenarioT() { failures += 1 }

        print("== U: routine — add, done today only, delete + Cmd+Z, persistence ==")
        if !scenarioU() { failures += 1 }

        print("== V: routine shortcuts — Cmd+R, Cmd+T then 1…7, Delete/Cmd+Z only in routine focus ==")
        if !scenarioV() { failures += 1 }

        print("== X: typography — list bullets, indents, links; markdown unchanged ==")
        if !scenarioX() { failures += 1 }

        print("== Y: sidebar hide/show keeps the tab; Cmd+R reveals it; breadcrumb switch ==")
        if !scenarioY() { failures += 1 }

        print("== W: routine streaks (demo data), reorder, drag target ==")
        if !scenarioW() { failures += 1 }

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    private static func makeRoutineState() -> AppState {
        let url = URL(fileURLWithPath: "/tmp/obf_selftest_routine.json")
        try? FileManager.default.removeItem(at: url)
        return AppState(
            store: DocumentStore(fileURL: URL(fileURLWithPath: "/tmp/obf_selftest_document.md")),
            routineStore: RoutineStore(fileURL: url))
    }

    /// Runs the main run loop until `condition` holds (deferred day
    /// switches land a run-loop pass later) or a second has passed.
    private static func pump(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(1)
        while !condition(), Date() < deadline {
            pump()
        }
    }

    private static func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    private static func scenarioU() -> Bool {
        let state = makeRoutineState()
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            if !cond { print("    FAIL: \(label)"); ok = false }
        }
        func texts(_ day: Int) -> [String] { state.routine.tasks(on: day).map(\.text) }
        func task(_ text: String) -> RoutineTask { state.routine.tasks.first { $0.text == text }! }
        let today = state.todayKey

        state.addRoutineItem("  Подъём в 8 утра \n", days: Array(0..<7))
        state.addRoutineItem("Зал", days: [0])
        state.addRoutineItem("Пара", days: [0, 2])
        state.addRoutineItem("   ", days: [0])
        state.addRoutineItem("Без дней", days: [])
        check(texts(0) == ["Подъём в 8 утра", "Зал", "Пара"], "add/trim/order")
        check(state.routine.tasks.count == 3, "one task per add, empty ignored")
        check(texts(2) == ["Подъём в 8 утра", "Пара"] && texts(1) == ["Подъём в 8 утра"], "repeat days")
        check(task("Пара").created == today && task("Пара").schedule == [RoutineScheduleEntry(from: today, days: [0, 2])], "schedule")

        // Done: logged by date, shared by all days of the task, resets next day.
        state.toggleRoutineDone(task("Зал").id)
        check(state.isRoutineItemDone(task("Зал")) && task("Зал").done == [today], "done logged")
        // Monday's list sinks done cards only when Monday is today.
        check(state.routineItemsForDisplay(day: 0).map(\.text)
              == (state.routineToday == 0 ? ["Подъём в 8 утра", "Пара", "Зал"] : ["Подъём в 8 утра", "Зал", "Пара"]),
              "done sinks on today's list only")
        check(texts(0) == ["Подъём в 8 утра", "Зал", "Пара"], "stored order kept")
        state.toggleRoutineDone(task("Зал").id)
        check(task("Зал").done.isEmpty, "undone removes date")
        state.toggleRoutineDone(task("Зал").id)

        // Text edit changes the task everywhere; days edit moves it.
        state.updateRoutineItem(task("Пара").id, text: "Пара АСОИУ", days: [1, 2])
        check(texts(0) == ["Подъём в 8 утра", "Зал"] && texts(1) == ["Подъём в 8 утра", "Пара АСОИУ"]
              && texts(2) == ["Подъём в 8 утра", "Пара АСОИУ"], "edit text + days")
        check(task("Пара АСОИУ").schedule.count == 1 && task("Пара АСОИУ").schedule[0].days == [1, 2],
              "same-day schedule changes collapse")

        // Delete from one day only (the shown one); Cmd+Z restores it.
        state.showRoutine(day: 2)
        pump(until: { state.routineDay == 2 })
        let para = task("Пара АСОИУ").id
        state.selectRoutineItem(para)
        state.deleteSelectedRoutineItems()
        check(texts(2) == ["Подъём в 8 утра"] && texts(1).contains("Пара АСОИУ"), "delete from this day only")
        check(task("Пара АСОИУ").currentDays == [1] && !task("Пара АСОИУ").isDeleted, "still on Tuesday")
        state.undoRoutineDeletion()
        pump(until: { state.routineDay == 2 })
        check(texts(2) == ["Подъём в 8 утра", "Пара АСОИУ"] && task("Пара АСОИУ").currentDays == [1, 2], "undo day delete")
        check(state.selectedRoutineItemIDs == [para], "restored card selected")

        // Shift+click multi-select, Delete removes all, one Cmd+Z brings all back in place.
        state.showRoutine(day: 0)
        pump(until: { state.routineDay == 0 })
        let rise = task("Подъём в 8 утра").id, zal = task("Зал").id
        state.clickRoutineItem(rise, day: 0, clickCount: 1)
        state.clickRoutineItem(zal, day: 0, clickCount: 1, shift: true)
        check(state.selectedRoutineItemIDs == [rise, zal], "shift adds")
        state.clickRoutineItem(zal, day: 0, clickCount: 1, shift: true)
        check(state.selectedRoutineItemIDs == [rise], "shift removes")
        state.clickRoutineItem(zal, day: 0, clickCount: 1, shift: true)
        state.deleteSelectedRoutineItems()
        check(texts(0).isEmpty, "group delete")
        check(task("Зал").isDeleted && task("Зал").deleted == today, "last day -> archived")
        check(!task("Подъём в 8 утра").isDeleted && task("Подъём в 8 утра").currentDays == Set(1..<7), "every-day task loses Monday")
        state.undoRoutineDeletion()
        pump()
        check(texts(0) == ["Подъём в 8 утра", "Зал"], "group undo in place")
        check(!task("Зал").isDeleted && task("Зал").done == [today], "archive undone, done kept")
        check(task("Подъём в 8 утра").currentDays.count == 7, "schedule restored")
        check(!state.undoRoutineDeletion(), "empty undo stack")

        // Plain click toggles a single selection; double click edits.
        state.clickRoutineItem(zal, day: 0, clickCount: 1)
        check(state.selectedRoutineItemIDs == [zal], "click selects one")
        state.clickRoutineItem(zal, day: 0, clickCount: 1)
        check(state.selectedRoutineItemIDs.isEmpty, "second click deselects")
        state.clickRoutineItem(zal, day: 0, clickCount: 1)
        state.clickRoutineItem(zal, day: 0, clickCount: 2)
        check(state.selectedRoutineItemIDs == [zal] && state.routineEditor?.itemID == zal, "double click edits")
        state.routineEditor = nil

        // "Удалить из всех дней": archived everywhere, undoable.
        state.deleteRoutineTaskEverywhere(rise, day: 0)
        check((0..<7).allSatisfy { !texts($0).contains("Подъём в 8 утра") } && task("Подъём в 8 утра").isDeleted,
              "delete everywhere")
        state.undoRoutineDeletion()
        pump()
        check((0..<7).allSatisfy { texts($0).first == "Подъём в 8 утра" }, "undo delete everywhere")

        // Leaving routine focus drops the undo history.
        state.selectRoutineItem(zal)
        state.deleteSelectedRoutineItems()
        state.endRoutineKeyFocus()
        check(!state.undoRoutineDeletion(), "undo dropped after focus left")

        // A schedule change on a later day opens a new period.
        var t = task("Пара АСОИУ")
        t.setDays([1, 5], from: "2099-01-01")
        check(t.schedule.map(\.from) == [today, "2099-01-01"] && t.currentDays == [1, 5], "new period")
        t.setDays([1, 2], from: "2099-01-01")
        check(t.schedule.count == 1, "reverting same day drops the period")

        // Day picker: every day lights all days; a day tapped after that
        // drops both itself and "every day".
        var picked: Set<Int> = [3]
        picked = RoutineDayPicker.toggledEveryDay(picked)
        check(picked == Set(0..<7), "every day selects all")
        picked = RoutineDayPicker.toggled(picked, 2)
        check(picked == [0, 1, 3, 4, 5, 6], "day off -> every day off")

        // Done marks reset on the next day.
        state.refreshToday(Date().addingTimeInterval(86_400))
        check(!state.isRoutineItemDone(task("Пара АСОИУ")), "fresh next day")

        // Persistence round-trip and readable format.
        let reloaded = RoutineStore(fileURL: state.routineStore.fileURL).load()
        check(reloaded == state.routine, "json round-trip")
        let json = (try? String(contentsOf: state.routineStore.fileURL, encoding: .utf8)) ?? ""
        check(json.contains("\"version\" : 2") && json.contains("\"tue\"") && json.contains("\"tuesday\""),
              "readable json")

        // A routine from the old per-day format is set aside, not loaded.
        let url = URL(fileURLWithPath: "/tmp/obf_selftest_routine_v1.json")
        let aside = URL(fileURLWithPath: "/tmp/obf_selftest_routine_v1.v1.json")
        try? FileManager.default.removeItem(at: aside)
        try? #"{"monday":[{"id":"5C2A7D1E-2B7C-4B4E-9E4B-1C2D3E4F5A6B","text":"Зал"}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let fresh = RoutineStore(fileURL: url).load()
        check(fresh.tasks.isEmpty && FileManager.default.fileExists(atPath: aside.path)
              && !FileManager.default.fileExists(atPath: url.path), "v1 set aside")
        print("    ok=\(ok)")
        return ok
    }

    private static func scenarioV() -> Bool {
        let state = makeRoutineState()
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            if !cond { print("    FAIL: \(label)"); ok = false }
        }
        let now = Date()
        state.sidebarTab = .tasks
        // Cmd+R alone: routine tab on today, no chord armed.
        check(RoutineKeys.handle(key(RoutineKeys.keyR, "r", .command), appState: state, now: now), "cmd+r consumed")
        check(state.sidebarTab == .routine && state.routineDay == state.routineToday, "cmd+r shows today")
        check(!RoutineKeys.handle(key(18, "1", .command), appState: state, now: now), "cmd+r does not arm digits")
        // Cmd+T, then Cmd+3: Wednesday (layout-independent: "е").
        state.sidebarTab = .structure
        check(RoutineKeys.handle(key(RoutineKeys.keyT, "е", .command), appState: state, now: now), "cmd+t consumed")
        check(state.sidebarTab == .structure, "cmd+t alone changes nothing")
        check(RoutineKeys.handle(key(20, "3", .command), appState: state, now: now.addingTimeInterval(0.5)), "digit consumed")
        pump(until: { state.routineDay == 2 })
        check(state.sidebarTab == .routine && state.routineDay == 2, "cmd+t 3 -> Wednesday")
        // Digit after the chord window is not taken.
        _ = RoutineKeys.handle(key(RoutineKeys.keyT, "t", .command), appState: state, now: now)
        check(!RoutineKeys.handle(key(18, "1", .command), appState: state, now: now.addingTimeInterval(3)), "late digit passes")
        // Plain Cmd+1 without Cmd+T passes through (heading).
        check(!RoutineKeys.handle(key(18, "1", .command), appState: state, now: now), "cmd+1 passes")
        // Cmd+T then 7 (Cmd released): Sunday.
        _ = RoutineKeys.handle(key(RoutineKeys.keyT, "t", .command), appState: state, now: now)
        _ = RoutineKeys.handle(key(26, "7"), appState: state, now: now)
        pump(until: { state.routineDay == 6 })
        check(state.routineDay == 6, "cmd+t 7 -> Sunday")

        // Delete / Cmd+Z only while a card has the keys.
        state.addRoutineItem("Бег", days: [6])
        state.addRoutineItem("Растяжка", days: [6])
        check(!RoutineKeys.handle(key(RoutineKeys.keyZ, "z", .command), appState: state), "cmd+z passes without focus")
        let ids = state.routine.order[6]
        state.selectRoutineItem(ids[0])
        state.selectRoutineItem(ids[1], extend: true)
        check(RoutineKeys.handle(key(RoutineKeys.keyBackspace, "\u{7F}"), appState: state), "delete consumed")
        check(state.routine.tasks(on: 6).isEmpty, "both deleted by key")
        check(RoutineKeys.handle(key(RoutineKeys.keyZ, "я", .command), appState: state), "cmd+z consumed")
        pump(until: { state.routineDay == 6 })
        check(state.routine.tasks(on: 6).map(\.text) == ["Бег", "Растяжка"], "restored by one cmd+z")
        state.endRoutineKeyFocus()
        check(!RoutineKeys.handle(key(RoutineKeys.keyBackspace, "\u{7F}"), appState: state), "delete passes after focus left")

        // Cmd+Shift+letter opens a tab from anywhere, revealing the sidebar.
        let sidebarWas = state.sidebarVisible
        check(RoutineKeys.handle(key(17, "t", [.command, .shift]), appState: state) && state.sidebarTab == .tasks,
              "cmd+shift+T -> Задания")
        state.setSidebarVisible(false)
        check(RoutineKeys.handle(key(3, "а", [.command, .shift]), appState: state)
              && state.sidebarTab == .files && state.sidebarVisible, "cmd+shift+F reveals Файлы (ru layout)")
        check(!RoutineKeys.handle(key(0, "a", [.command, .shift]), appState: state), "cmd+shift+A is not ours")
        // Cmd+K picker: arrows + Return, digits, letters, Esc; swallows the rest.
        check(RoutineKeys.handle(key(RoutineKeys.keyK, "k", .command), appState: state) && state.tabPickerVisible,
              "cmd+K opens the picker")
        check(state.tabPickerIndex == SidebarTab.files.rawValue, "picker starts on the open tab")
        _ = RoutineKeys.handle(key(RoutineKeys.keyDown, ""), appState: state)
        _ = RoutineKeys.handle(key(RoutineKeys.keyDown, ""), appState: state)
        check(state.tabPickerIndex == 0, "arrow wraps around")
        check(RoutineKeys.handle(key(0, "a"), appState: state) && state.tabPickerVisible, "other keys swallowed")
        _ = RoutineKeys.handle(key(RoutineKeys.keyUp, ""), appState: state)
        _ = RoutineKeys.handle(key(RoutineKeys.keyReturn, "\r"), appState: state)
        check(!state.tabPickerVisible && state.sidebarTab == .control, "Return opens the highlighted tab")
        state.setSidebarVisible(false)
        _ = RoutineKeys.handle(key(RoutineKeys.keyK, "k", .command), appState: state)
        _ = RoutineKeys.handle(key(20, "3"), appState: state)
        check(state.sidebarTab == .deadlines && state.sidebarVisible && !state.tabPickerVisible, "digit 3 -> Дедлайны")
        _ = RoutineKeys.handle(key(RoutineKeys.keyK, "k", .command), appState: state)
        _ = RoutineKeys.handle(key(1, "ы"), appState: state)
        check(state.sidebarTab == .structure && !state.tabPickerVisible, "letter S -> Структура")
        _ = RoutineKeys.handle(key(RoutineKeys.keyK, "k", .command), appState: state)
        _ = RoutineKeys.handle(key(RoutineKeys.keyEscape, "\u{1B}"), appState: state)
        check(!state.tabPickerVisible && state.sidebarTab == .structure, "Esc closes without change")
        check(Set(SidebarTab.allCases.map(\.shortcutLetter)).count == SidebarTab.allCases.count, "letters unique")
        state.setSidebarVisible(sidebarWas)
        print("    day=\(state.routineDay) ok=\(ok)")
        return ok
    }

    private static func scenarioW() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            if !cond { print("    FAIL: \(label)"); ok = false }
        }
        // Fixed Thursday so the demo's weekday-relative tasks are stable.
        let today = "2026-09-24"
        check(RoutineDate.weekday(today) == 3, "2026-09-24 is Thursday")
        check(RoutineDate.adding(-7, to: "2026-03-31") == "2026-03-24"
              && RoutineDate.adding(1, to: "2026-10-24") == "2026-10-25", "date math across DST")
        let data = RoutineDemo.data(today: today)
        func streak(_ text: String, _ day: String = today) -> RoutineStreak {
            data.tasks.first { $0.text.hasPrefix(text) }!.streak(today: day)
        }
        func weekly(_ pairs: [(Int, Int)]) -> RoutineStreak { .weekly(pairs.map { (day: $0.0, count: $0.1) }) }
        check(streak("Подъём") == .daily(12), "daily 12: \(streak("Подъём"))")
        check(streak("Чтение") == .daily(5), "daily incl. today 5: \(streak("Чтение"))")
        check(streak("Пара") == weekly([(1, 3), (3, 5), (5, 1)]), "ВТ-3 ЧТ-5 СБ-1: \(streak("Пара"))")
        check(streak("Зал") == weekly([(0, 3), (2, 2), (4, 0)]), "ПН-3 СР-2 ПТ-0: \(streak("Зал"))")
        check(streak("Генеральная") == weekly([(6, 4)]), "ВС-4: \(streak("Генеральная"))")
        check(streak("1 час") == weekly([(3, 2)]), "ЧТ-2: \(streak("1 час"))")
        check(streak("Статья").isEmpty, "new task: no streak")
        check(streak("Задача «А»") == weekly([(3, 3)]), "biweekly on: ×3: \(streak("Задача «А»"))")
        check(streak("Задача «Б»") == weekly([(3, 2)]), "biweekly off: ×2: \(streak("Задача «Б»"))")

        // Marking today extends the streak; a day passing unmarked breaks it.
        var rise = data.tasks.first { $0.text.hasPrefix("Подъём") }!
        rise.done.append(today)
        check(rise.streak(today: today) == .daily(13), "today done -> 13")
        check(rise.streak(today: RoutineDate.adding(1, to: today)) == .daily(13), "next morning still 13")
        check(rise.streak(today: RoutineDate.adding(2, to: today)) == .daily(0), "missed day -> 0")
        var lecture = data.tasks.first { $0.text.hasPrefix("Пара") }!
        lecture.done.append(today)
        check(lecture.streak(today: today) == weekly([(1, 3), (3, 6), (5, 1)]), "ЧТ-6 after marking today")

        // Every other week: due on alternate Thursdays, off weeks neither
        // due nor missed, streak counts due Thursdays only.
        check(RoutineDate.weeksBetween("2026-09-21", "2026-10-08") == 2
              && RoutineDate.weeksBetween("2026-09-27", "2026-09-28") == 1
              && RoutineDate.weeksBetween("2026-10-08", "2026-09-24") == -2, "weeks between")
        check(RoutineDate.short("2026-10-01") == "1.10" && RoutineDate.short("2026-09-24") == "24.09", "short date")
        var ab = RoutineTask(text: "А", created: "2026-09-24", schedule: [RoutineScheduleEntry(
            from: "2026-09-24", days: [3], everyWeeks: 2, anchor: "2026-09-21")])
        check(ab.isScheduled(on: "2026-09-24") && !ab.isScheduled(on: "2026-10-01")
              && ab.isOffWeek(on: "2026-10-01") && ab.isScheduled(on: "2026-10-08"), "alternate Thursdays")
        check(ab.nextDueDate(after: "2026-09-24") == "2026-10-08", "next due")
        ab.done = ["2026-09-24", "2026-10-08"]
        check(ab.streak(today: "2026-10-15") == weekly([(3, 2)]), "streak skips off week")
        check(ab.streak(today: "2026-10-22") == weekly([(3, 2)]), "22.10 not marked yet: holds")
        check(ab.streak(today: "2026-10-23") == weekly([(3, 0)]), "22.10 passed unmarked: breaks")
        // Starting next week: this week's Thursday is not due.
        let late = RoutineTask(text: "Б", created: "2026-09-24", schedule: [RoutineScheduleEntry(
            from: "2026-09-24", days: [3], everyWeeks: 2, anchor: "2026-09-28")])
        check(!late.isScheduled(on: "2026-09-24") && late.nextDueDate(after: "2026-09-24") == "2026-10-01",
              "start next week")
        check(Weekday.interval(2) == "через неделю" && Weekday.interval(3) == "раз в 3 недели"
              && Weekday.interval(5) == "раз в 5 недель" && Weekday.interval(21) == "раз в 21 неделю"
              && Weekday.interval(1) == nil, "interval wording")
        // Round-trip keeps the plan; weekly entries stay in the short form.
        let encoded = try! JSONEncoder().encode(ab)
        check(try! JSONDecoder().decode(RoutineTask.self, from: encoded) == ab, "interval round-trip")
        let weeklyJSON = String(data: try! JSONEncoder().encode(RoutineScheduleEntry(from: today, days: [1])), encoding: .utf8)!
        check(!weeklyJSON.contains("everyWeeks") && !weeklyJSON.contains("anchor"), "weekly stays short")
        // Switching a task from weekly to every other week and back.
        var plan = RoutineTask(text: "В", created: today, schedule: [RoutineScheduleEntry(from: today, days: [3])])
        plan.setPlan(RoutineScheduleEntry(from: today, days: [3], everyWeeks: 2, anchor: RoutineDate.weekStart(today)), from: "2099-01-01")
        check(plan.schedule.count == 2 && plan.everyWeeks == 2, "interval change is a new period")
        plan.setDays([3, 5], from: "2099-01-01")
        check(plan.everyWeeks == 2 && plan.currentDays == [3, 5] && plan.schedule.count == 2, "day change keeps interval")
        // Display: off-week tasks sink below done ones and are not counted.
        let biState = makeRoutineState()
        let d = biState.routineToday
        biState.addRoutineItem("Вкл", days: [d], everyWeeks: 2, startOffset: 0)
        biState.addRoutineItem("Выкл", days: [d], everyWeeks: 2, startOffset: 1)
        biState.addRoutineItem("Обычная", days: [d])
        biState.toggleRoutineDone(biState.routine.order[d][2])
        check(biState.routineItemsForDisplay(day: d).map(\.text) == ["Вкл", "Обычная", "Выкл"], "off week at the bottom")
        check(!biState.isRoutineItemActive(biState.routine.tasks(on: d)[1], day: d), "off this week")

        // Time of day: parsing, formatting while typing, labels, rules.
        check(RoutineTime.format("1555") == "15:55" && RoutineTime.format("155") == "15:5"
              && RoutineTime.format("15:") == "15" && RoutineTime.format("12a34567") == "12:34", "time typing")
        check(RoutineTime.parse("15:55") == .time("15:55") && RoutineTime.parse("") == .empty
              && RoutineTime.parse("24:24") == .invalid && RoutineTime.parse("12:60") == .invalid
              && RoutineTime.parse("15:5") == .invalid && RoutineTime.parse("00:00") == .time("00:00"), "time parse")
        func timeResult(_ a: String, _ b: String) -> String {
            switch RoutineTime.from(start: a, end: b) {
            case .success(let time): return time?.label ?? "none"
            case .failure(let error): return "\(error)"
            }
        }
        check(timeResult("15:55", "17:25") == "с 15:55 до 17:25", "both ends")
        check(timeResult("09:00", "") == "с 09:00" && timeResult("", "23:00") == "до 23:00", "one end")
        check(timeResult("", "") == "none", "no time")
        check(timeResult("24:24", "") == "start" && timeResult("", "9") == "end", "bad field")
        check(timeResult("23:00", "01:00") == "order" && timeResult("10:00", "10:00") == "order", "within one day")
        let timed = makeRoutineState()
        timed.addRoutineItem("Пара", days: [1], time: RoutineTime(start: "15:55", end: "17:25"))
        let timedID = timed.routine.tasks[0].id
        check(timed.routine.tasks[0].time?.label == "с 15:55 до 17:25", "time stored")
        timed.updateRoutineItem(timedID, text: "Пара", days: [1], time: RoutineTime(end: "18:00"))
        check(timed.routine.tasks[0].time == RoutineTime(end: "18:00")
              && timed.routine.tasks[0].schedule.count == 1, "time edit keeps no history")
        timed.updateRoutineItem(timedID, text: "Пара", days: [1], time: nil)
        let untimedJSON = String(data: try! JSONEncoder().encode(timed.routine.tasks[0]), encoding: .utf8)!
        check(timed.routine.tasks[0].time == nil && !untimedJSON.contains("time"), "time removed, file unchanged")

        // Reorder keeps done cards in their stored slots.
        let state = makeRoutineState()
        for text in ["A", "B", "C", "D"] { state.addRoutineItem(text, days: [state.routineToday]) }
        let day = state.routineToday
        let ids = state.routine.order[day]
        state.toggleRoutineDone(ids[1])
        state.reorderRoutineItems(day: day, activeOrder: [ids[3], ids[0], ids[2]])
        check(state.routine.tasks(on: day).map(\.text) == ["D", "B", "A", "C"], "reorder around done slot")
        check(state.routineItemsForDisplay(day: day).map(\.text) == ["D", "A", "C", "B"], "display after reorder")
        check(RoutineStore(fileURL: state.routineStore.fileURL).load().order[day] == state.routine.order[day], "order saved")

        // Bug repro: a task done today on another weekday's list must not
        // sink there — dragging it to the top of that day must stick.
        let other = (day + 1) % 7
        for text in ["X", "Y", "Z"] { state.addRoutineItem(text, days: [day, other]) }
        let z = state.routine.tasks.first { $0.text == "Z" }!.id
        state.toggleRoutineDone(z)
        check(state.routineItemsForDisplay(day: other).map(\.text) == ["X", "Y", "Z"], "no done-sinking on other days")
        let otherIDs = state.routine.order[other]
        state.reorderRoutineItems(day: other, activeOrder: [z] + otherIDs.filter { $0 != z })
        check(state.routineItemsForDisplay(day: other).map(\.text) == ["Z", "X", "Y"], "moved to top sticks")
        check(state.routineItemsForDisplay(day: day).last?.text == "Z", "still sinks on today's list")

        // Drag target: cards of height 40 stacked from 0 with spacing 8.
        let a = UUID(), b = UUID(), c = UUID()
        let heights = [a: CGFloat(40), b: 40, c: 40]
        func target(_ center: CGFloat) -> [UUID] {
            RoutineDayListTesting.targetOrder(dragged: a, center: center, order: [a, b, c], heights: heights, top: 0)
        }
        check(target(10) == [a, b, c], "stays on top")
        check(target(30) == [b, a, c], "past b's middle")
        check(target(90) == [b, c, a], "to the bottom")
        print("    ok=\(ok)")
        return ok
    }

    private static func makeStack() -> (AppState, OBFTextView, Coordinator, NSTextStorage) {
        // Tests write to a temp file: the debounced auto-save must never
        // touch the real document.
        let appState = AppState(store: DocumentStore(fileURL: URL(fileURLWithPath: "/tmp/obf_selftest_document.md")))
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        coordinator.loadDocument()
        // Work on a fresh, deterministic document instead of the real file.
        storage.setAttributedString(NSAttributedString())
        return (appState, textView, coordinator, storage)
    }

    private static func type(_ textView: OBFTextView, _ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Lets deferred main-queue work (typing-attribute sync, restyling)
    /// run, the way it would between real keystrokes.
    private static func pump() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    /// A paragraph's level is the marker on its first character; the trailing
    /// newline never carries it. Empty paragraphs report nil.
    private static func paragraphMarkers(_ storage: NSTextStorage) -> [String] {
        let ns = storage.string as NSString
        var levels: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, _, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let last = ns.character(at: NSMaxRange(enclosing) - 1)
            let contentLength = (last == 0x0A || last == 0x0D) ? enclosing.length - 1 : enclosing.length
            guard contentLength > 0 else { levels.append("empty"); return }
            if let task = storage.attribute(.obfTaskState, at: enclosing.location, effectiveRange: nil) as? Int {
                levels.append(task == 2 ? "done" : "task")
                return
            }
            levels.append(storage.attribute(.obfHeadingLevel, at: enclosing.location, effectiveRange: nil) as? Int == 1 ? "H1"
                        : storage.attribute(.obfHeadingLevel, at: enclosing.location, effectiveRange: nil) as? Int == 2 ? "H2"
                        : "body")
        }
        return levels
    }

    private static func dump(_ label: String, _ textView: OBFTextView, _ storage: NSTextStorage) {
        let marker = textView.typingAttributes[.obfHeadingLevel] as? Int
        let font = textView.typingAttributes[.font] as? NSFont
        let sel = textView.selectedRange()
        print("  [\(label)] sel=(\(sel.location),\(sel.length)) typing marker=\(marker.map(String.init) ?? "nil") font=\(font.map { "\($0.pointSize)pt" } ?? "nil")")
        print("    storage: \(storage.string.debugDescription)")
        print("    paragraphs: \(paragraphMarkers(storage))")
    }

    private static func typedCharIsBody(_ textView: OBFTextView, _ storage: NSTextStorage, appState: AppState) -> Bool {
        let index = textView.selectedRange().location - 1
        guard index >= 0 else { return false }
        let marker = storage.attribute(.obfHeadingLevel, at: index, effectiveRange: nil) as? Int
        let size = (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize
        return marker == nil && size == appState.bodyFont.pointSize
    }

    /// Heading with text typed below it: Enter exits to body, further edits
    /// must not bring the heading style back.
    private static func scenarioA() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        type(textView, "обычный текст")
        textView.insertNewline(nil)
        textView.deleteBackward(nil)
        dump("after Backspace", textView, storage)
        pump()

        let markerBefore = paragraphMarkers(storage)
        let typingClean = textView.typingAttributes[.obfHeadingLevel] == nil
        type(textView, "X")
        dump("after typing X", textView, storage)

        let ok = typingClean && typedCharIsBody(textView, storage, appState: appState) && paragraphMarkers(storage) == markerBefore
        print("    -> OK: \(ok)")
        return ok
    }

    /// Exact user repro: heading, Enter (empty line below), Enter again,
    /// Backspace — caret ends on the empty line under the heading; typing
    /// there must stay body text.
    private static func scenarioB() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        textView.insertNewline(nil)
        textView.deleteBackward(nil)
        dump("after Backspace", textView, storage)
        pump()

        let markerBefore = paragraphMarkers(storage)
        let typingClean = textView.typingAttributes[.obfHeadingLevel] == nil
        type(textView, "X")
        dump("after typing X", textView, storage)

        let ok = typingClean
            && typedCharIsBody(textView, storage, appState: appState)
            && paragraphMarkers(storage) == ["H1", "body"]
            && markerBefore == ["H1"]
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+1 on an empty line directly under a heading must turn THAT line
    /// into a heading (via typing attributes) and must not touch the heading
    /// above.
    private static func scenarioC() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "Заголовок")
        coordinator.setHeadingLevel(1)
        textView.insertNewline(nil)
        // Caret is now on the empty line under the heading.
        coordinator.setHeadingLevel(1)
        dump("after Cmd+1 on empty line", textView, storage)
        type(textView, "X")
        dump("after typing X", textView, storage)

        let markers = paragraphMarkers(storage)
        let ok = markers == ["H1", "H1"]
        print("    -> OK: \(ok) (markers: \(markers))")
        return ok
    }

    /// findNext/findPrev must cycle through matches endlessly: with 3 matches
    /// four findNext calls visit 1, 2, 3, then wrap back to 1.
    private static func scenarioD() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()

        type(textView, "X один\nX два\nX три")
        appState.findQuery = "X"
        coordinator.updateFindMatches()

        var indexes: [Int] = [appState.currentMatchIndex]
        for _ in 0..<4 {
            coordinator.findNext()
            indexes.append(appState.currentMatchIndex)
        }
        coordinator.findPrev()
        indexes.append(appState.currentMatchIndex)

        let ok = appState.matches.count == 3 && indexes == [0, 1, 2, 0, 1, 0]
        print("    matches=\(appState.matches.count) indexes=\(indexes) -> OK: \(ok)")
        return ok
    }

    /// Closing the find bar removes the highlight for good: neither a later
    /// updateFindMatches (the debounced refresh after edits) nor typing may
    /// bring the highlight back while the bar is closed.
    private static func scenarioE() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        type(textView, "X один\nX два\nX три")
        appState.findQuery = "X"
        appState.findVisible = true
        coordinator.updateFindMatches()
        let highlightedWhileOpen = hasBackgroundAttribute(storage)

        appState.findVisible = false
        coordinator.clearFindHighlight()
        let clearedAfterClose = !hasBackgroundAttribute(storage)

        // Simulates the 0.5s refresh that follows any edit: previously it
        // re-added the highlight even though the find bar was closed.
        coordinator.updateFindMatches()
        type(textView, "Y")
        let staysClear = !hasBackgroundAttribute(storage)

        print("    open=\(highlightedWhileOpen) closed=\(clearedAfterClose) staysClear=\(staysClear)")
        let ok = highlightedWhileOpen && clearedAfterClose && staysClear
        print("    -> OK: \(ok)")
        return ok
    }

    private static func hasBackgroundAttribute(_ storage: NSTextStorage) -> Bool {
        guard storage.length > 0 else { return false }
        var found = false
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// A long line must wrap at the text container width — the used layout
    /// rect must never be wider than the container.
    private static func scenarioF() -> Bool {
        let (_, textView, _, _) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        let longWord = String(repeating: "слово", count: 40)
        let longLine = (0..<60).map { _ in longWord }.joined(separator: " ")
        type(textView, longLine)
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)

        let used = layoutManager.usedRect(for: container)
        print("    frame=\(textView.frame.width) container=\(container.containerSize.width) used=\(used.width)")
        let ok = container.containerSize.width > 0 && used.width <= container.containerSize.width + 0.5
        print("    -> OK: \(ok)")
        return ok
    }

    /// Crash repro: the user selects a stretch of text and starts typing
    /// without deleting first. In the app this died inside
    /// -[NSTextStorage ensureAttributesAreFixedInRange:] during drawRect, so
    /// besides replacing the characters we force a full layout and display
    /// pass here. Also exercised with an active find highlight over the
    /// selection — the highlight is a plain background attribute and the most
    /// invasive storage mutation we do outside of plain typing.
    private static func scenarioG() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        type(textView, "Первая строка\nВторая строка\nТретья строка")
        let full = NSRange(location: 0, length: storage.length)

        // Plain: select across paragraphs, type over it.
        textView.setSelectedRange(full)
        type(textView, "замена")
        var ok = storage.string == "замена"

        // With a live find highlight sitting on the replaced range.
        type(textView, "\nальфа бета альфа")
        appState.findQuery = "альфа"
        appState.findVisible = true
        coordinator.updateFindMatches()
        let highlighted = hasBackgroundAttribute(storage)
        textView.setSelectedRange(NSRange(location: 6, length: storage.length - 6))
        type(textView, "гамма")
        let survived = storage.string == "замена\ngамма" || storage.string.hasPrefix("замена")
        appState.findVisible = false
        coordinator.clearFindHighlight()

        // Force the drawing path that crashed: full layout + display.
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)
        textView.display()

        print("    replaced ok=\(ok) highlighted=\(highlighted) after=\(storage.string.debugDescription)")
        ok = ok && highlighted && survived
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+F must drop the pre-existing selection; the match highlight must
    /// survive edits, whole-document restyles (zoom) and background
    /// refreshes; closing find must remove both the highlight and any
    /// selection left in the text.
    private static func scenarioH() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()
        appState.editor = coordinator

        type(textView, "альфа бета\nальфа гамма\nальфа дельта")

        // A selection made before searching must be cleared by Cmd+F.
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        appState.findQuery = "альфа"
        appState.showFindBar()
        let selectionClearedOnOpen = textView.selectedRange().length == 0
        let highlightedOnOpen = hasBackgroundAttribute(storage)

        // Typing restyles the paragraph on the next run-loop turn; the
        // highlight must be re-applied there, not 0.5 s later.
        type(textView, "!")
        pump()
        let highlightedAfterEdit = hasBackgroundAttribute(storage)

        // Zoom restyles the whole document without any character edit.
        // bodyPointSize persists to UserDefaults, so restore it afterwards —
        // otherwise every test run would leak a zoom step.
        let savedPointSize = appState.bodyPointSize
        coordinator.zoomIn()
        let highlightedAfterZoom = hasBackgroundAttribute(storage)
        appState.bodyPointSize = savedPointSize

        // Closing find removes the highlight and any selection.
        textView.setSelectedRange(NSRange(location: 2, length: 3))
        appState.closeFind()
        let clearedOnClose = !hasBackgroundAttribute(storage) && textView.selectedRange().length == 0

        print("    open: selCleared=\(selectionClearedOnOpen) highlighted=\(highlightedOnOpen)")
        print("    afterEdit=\(highlightedAfterEdit) afterZoom=\(highlightedAfterZoom) clearedOnClose=\(clearedOnClose)")
        let ok = selectionClearedOnOpen && highlightedOnOpen && highlightedAfterEdit && highlightedAfterZoom && clearedOnClose
        print("    -> OK: \(ok)")
        return ok
    }

    /// Reproduces "lines overflow the working area until the first scroll":
    /// measures the editor geometry right after launch (no user actions) and
    /// again after a programmatic scroll, printing text view / clip view /
    /// text container widths and the rightmost laid-out line fragment.
    /// Also captures window snapshots for visual inspection of the sidebar:
    /// initial state, the tab list under a simulated hover over the tab
    /// title, and an empty tab. Launched with --uitest-open; exits the
    /// process when done.
    /// --uitest-routine: fills a demo routine and snapshots the routine
    /// tab (today, done marks, selection, another day, add/edit modals)
    /// to /tmp/obf_routine_*.png, then quits.
    static func snapRoutine(appState: AppState) {
        let today = appState.routineToday
        appState.addRoutineItem("Подъём в 8 утра", days: Array(0..<7))
        appState.addRoutineItem("Зал с 9 утра до 10:30", days: [0, 2, 4])
        appState.addRoutineItem("1 час на обучении: линал, ангем, тервер, матстат", days: [today])
        appState.addRoutineItem("1 час на изучении статей по диплому", days: [today])
        appState.addRoutineItem("Пара в 15:55 — Аналитические модели АСОИУ", days: [1, 3])
        appState.addRoutineItem("Бег 5 км", days: [(today + 1) % 7])
        appState.showRoutine(day: nil)
        func snap(_ window: NSWindow, _ name: String) {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_routine_\(name).png"))
            }
        }
        func after(_ t: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
        }
        after(1.0) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { exit(1) }
            snap(window, "1_today")
            let items = appState.routine.tasks(on: today)
            appState.toggleRoutineDone(items[0].id)
            appState.selectRoutineItem(items[1].id)
            appState.selectRoutineItem(items[2].id, extend: true)
            after(0.6) {
                snap(window, "2_done_selected")
                appState.selectRoutineDay((today + 1) % 7, forward: true)
                after(0.8) {
                    snap(window, "3_next_day")
                    appState.routineEditor = RoutineEditorRequest(day: appState.routineDay, itemID: nil)
                    after(0.8) {
                        if let sheet = window.attachedSheet { snap(sheet, "4_add_modal") }
                        appState.routineEditor = nil
                        after(0.8) {
                            appState.routineEditor = RoutineEditorRequest(
                                day: today, itemID: appState.routine.tasks(on: today).first?.id)
                        }
                        after(1.6) {
                            if let sheet = window.attachedSheet { snap(sheet, "4b_edit_modal") }
                            appState.routineEditor = nil
                        }
                        after(2.4) {
                            appState.selectRoutineDay((today + 2) % 7, forward: true)
                            after(0.8) {
                                snap(window, "5_empty_day")
                                print("ROUTINE-SNAP done")
                                exit(0)
                            }
                        }
                    }
                }
            }
        }
    }

    /// --uitest-typography: renders a copy of the real document in every
    /// document font (top of the file and scrolled, to show the breadcrumb
    /// and lists), plus the sidebar in the system vs. document font, to
    /// /tmp/obf_typo_*.png. Restores the persisted font settings, quits.
    static func snapTypography(appState: AppState) {
        let originalFont = appState.editorFont
        let originalUI = appState.uiFollowsEditor
        func snap(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/obf_typo_\(name).png"))
        }
        func scroll(to y: CGFloat) {
            guard let textView = (appState.editor as? Coordinator)?.debugTextView else { return }
            textView.scroll(NSPoint(x: 0, y: y))
        }
        var steps: [(Double, () -> Void)] = []
        appState.uiFollowsEditor = false
        for font in EditorFont.allCases {
            steps.append((0.7, { appState.editorFont = font; scroll(to: 0) }))
            steps.append((0.7, { snap("\(font.rawValue)_top"); scroll(to: 520) }))
            steps.append((0.5, { snap("\(font.rawValue)_scrolled") }))
        }
        steps.append((0.3, { appState.editorFont = .newYork; appState.sidebarTab = .routine }))
        steps.append((0.8, { snap("ui_system") ; appState.uiFollowsEditor = true }))
        steps.append((0.8, { snap("ui_document_font") }))
        steps.append((0.2, {
            appState.uiFollowsEditor = originalUI
            appState.editorFont = originalFont
            // exit() right away would drop the pending preference writes.
            UserDefaults.standard.synchronize()
            print("TYPO-SNAP done")
            exit(0)
        }))
        var delay = 1.0
        for (wait, step) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
    }

    /// --uitest-themes: the real document (a copy) in every colour theme,
    /// with the routine tab open, to /tmp/obf_theme_*.png; restores the
    /// persisted theme, quits.
    static func snapThemes(appState: AppState) {
        let original = appState.themeID
        func snap(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/obf_theme_\(name).png"))
        }
        var steps: [(Double, () -> Void)] = [(0, { appState.sidebarTab = .routine })]
        for theme in ColorTheme.all {
            steps.append((0.7, { appState.themeID = theme.id }))
            steps.append((0.7, {
                // A selection, to see its colour.
                if let textView = (appState.editor as? Coordinator)?.debugTextView {
                    textView.setSelectedRange(NSRange(location: 60, length: 40))
                }
                snap(theme.id)
            }))
        }
        steps.append((0.2, {
            appState.themeID = original
            UserDefaults.standard.synchronize()
            print("THEME-SNAP done")
            exit(0)
        }))
        var delay = 1.0
        for (wait, step) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
    }

    /// --uitest-outline: hovers a cut-short heading in "Структура" (the
    /// real cursor is moved there and back), snaps the tooltip, then folds
    /// the first foldable H1 and snaps again, to /tmp/obf_outline_*.png.
    static func snapOutline(appState: AppState) {
        let foldsWere = appState.collapsedOutline
        let restore = CGEvent(source: nil)?.location
        func snap(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/obf_outline_\(name).png"))
        }
        func hover(windowX: CGFloat, fromTop: CGFloat) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            let point = NSPoint(x: windowX, y: OBFTheme.windowHeight - fromTop)
            let screen = window.convertToScreen(CGRect(origin: point, size: .zero)).origin
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            CGWarpMouseCursorPosition(CGPoint(x: screen.x, y: mainHeight - screen.y))
            if let moved = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 0, pressure: 0) {
                NSApp.postEvent(moved, atStart: false)
            }
        }
        func after(_ t: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
        }
        appState.collapsedOutline = []
        appState.setSidebarVisible(true)
        appState.sidebarTab = .structure
        let x = OBFTheme.windowWidth - OBFTheme.contentPadding - OBFTheme.sidebarWidth + 90
        after(1.2) { hover(windowX: x, fromTop: 245) }
        after(1.4) { hover(windowX: x + 2, fromTop: 246) }
        after(2.4) {
            snap("1_tooltip")
            hover(windowX: 300, fromTop: 400)
            if let first = appState.outline.first(where: { appState.foldableOutlineIDs.contains($0.id) }) {
                appState.toggleOutlineFold(first)
            }
        }
        after(3.2) {
            snap("2_folded")
            appState.showTabPicker()
            appState.moveTabPicker(by: 1)
        }
        after(3.8) {
            snap("3_picker")
            appState.hideTabPicker()
            if let restore { CGWarpMouseCursorPosition(restore) }
            appState.collapsedOutline = foldsWere
            UserDefaults.standard.synchronize()
            print("OUTLINE-SNAP done")
            exit(0)
        }
    }

    /// --uitest-sidebar: hides and shows the sidebar (Cmd+S), snapping the
    /// window mid-animation and logging the text view width each frame to
    /// /tmp/obf_sidebar_*; restores the visibility, quits.
    static func snapSidebar(appState: AppState) {
        let original = appState.sidebarVisible
        func snap(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/obf_sidebar_\(name).png"))
        }
        var widths: [String] = []
        let start = Date()
        let sampler = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            if let textView = (appState.editor as? Coordinator)?.debugTextView {
                let y = textView.enclosingScrollView?.contentView.bounds.minY ?? -1
                widths.append("\(Int(Date().timeIntervalSince(start) * 1000) % 100000):\(Int(textView.frame.width))/y\(Int(y))")
            }
        }
        func after(_ t: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
        }
        appState.setSidebarVisible(true)
        after(1.0) {
            snap("1_shown")
            RunLoop.main.add(sampler, forMode: .common)
            appState.toggleSidebar()
            after(0.9) {
                snap("3_hidden")
                print("SIDEBAR hide widths: \(widths.joined(separator: " "))")
                widths = []
                appState.toggleSidebar()
                after(0.9) {
                    sampler.invalidate()
                    snap("5_shown_again")
                    print("SIDEBAR show widths: \(widths.joined(separator: " "))")
                    appState.setSidebarVisible(original)
                    UserDefaults.standard.synchronize()
                    print("SIDEBAR-SNAP done")
                    exit(0)
                }
            }
        }
    }

    static func measureOpen(appState: AppState) {
        func measure(_ label: String) {
            guard let coordinator = appState.editor as? Coordinator,
                  let textView = coordinator.debugTextView,
                  let lm = textView.layoutManager,
                  let tc = textView.textContainer,
                  let sv = textView.enclosingScrollView else {
                print("OPEN-MEASURE \(label): missing view stack")
                return
            }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            var maxRight: CGFloat = 0
            if lm.numberOfGlyphs > 0 {
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, _, _ in
                    maxRight = max(maxRight, rect.maxX)
                }
            }
            let overflow = maxRight > tc.containerSize.width + 0.5
                || textView.frame.width > sv.contentSize.width + 0.5
            print("OPEN-MEASURE \(label): tvW=\(textView.frame.width) clipW=\(sv.contentSize.width) contW=\(tc.containerSize.width) usedW=\(used.width) maxRight=\(maxRight) overflow=\(overflow)")
        }
        /// Renders the window's own view hierarchy — no screen-recording
        /// permission needed, unlike CGWindowListCreateImage.
        func snap(_ window: NSWindow, _ name: String) {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("OPEN-MEASURE snap \(name): FAILED")
                return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_open_\(name).png"))
            }
        }
        /// Opens the task modal for an active and then a done task,
        /// snapshotting the sheet window each time, then closes it.
        func snapTaskModals(_ window: NSWindow, then next: @escaping () -> Void) {
            appState.modalTaskID = appState.tasks.first(where: { !$0.done })?.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let sheet = window.attachedSheet
                print("OPEN-MEASURE task-modal active: sheet=\(sheet != nil) ok=\(sheet != nil)")
                if let sheet { snap(sheet, "9a_modal_active") }
                appState.modalTaskID = appState.tasks.first(where: { $0.done })?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if let sheet = window.attachedSheet { snap(sheet, "9b_modal_done") }
                    appState.modalTaskID = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        let closed = window.attachedSheet == nil
                        print("OPEN-MEASURE task-modal closed: ok=\(closed)")
                        next()
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            measure("t=0.8")
            guard let coordinator = appState.editor as? Coordinator,
                  let textView = coordinator.debugTextView,
                  let sv = textView.enclosingScrollView,
                  let window = textView.window,
                  let content = window.contentView else { exit(1) }
            snap(window, "1_initial")

            /// Posts a synthetic trackpad-style scroll event (with gesture
            /// phase) at a window point — lets the swipe pipeline be tested
            /// end to end without real touch input. Phase values mirror
            /// NSEvent.Phase raw values: 1 = began, 2 = changed, 4 = ended.
            func postScroll(at point: NSPoint, phase: Int64, dx: Int32, dy: Int32) {
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let cg = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                let screenRect = window.convertToScreen(CGRect(origin: point, size: .zero))
                let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                cg.location = CGPoint(x: screenRect.origin.x, y: mainHeight - screenRect.origin.y)
                if let nsEvent = NSEvent(cgEvent: cg) {
                    NSApplication.shared.postEvent(nsEvent, atStart: false)
                }
            }
            func swipe(at point: NSPoint, dx: Int32, dy: Int32, steps: Int) {
                postScroll(at: point, phase: 1, dx: 0, dy: 0)
                for _ in 0..<steps {
                    postScroll(at: point, phase: 2, dx: dx, dy: dy)
                }
                postScroll(at: point, phase: 4, dx: 0, dy: 0)
            }

            let sidebarPoint = NSPoint(x: 924 + 130, y: 400)
            let editorPoint = NSPoint(x: 400, y: 400)
            SelfTest.loggingScrollEvents = true
            appState.sidebarTab = .structure
            swipe(at: sidebarPoint, dx: -15, dy: 0, steps: 6)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // Assert direction relative to the deltas the monitor
                // actually saw, so CG→NS sign mapping cannot skew the test.
                let sawNegativeX = SelfTest.debugScrollLog.contains { $0.contains("dx=-") }
                let expected: SidebarTab = sawNegativeX ? .tasks : .structure
                let leftOK = appState.sidebarTab == expected
                print("OPEN-MEASURE swipe-over-sidebar: tab=\(appState.sidebarTab.title) expected=\(expected.title) ok=\(leftOK)")
                print("OPEN-MEASURE scroll-log: \(SelfTest.debugScrollLog)")
                SelfTest.debugScrollLog = []
                // Vertical gesture and horizontal gesture over the editor
                // must NOT switch tabs.
                swipe(at: sidebarPoint, dx: 0, dy: -15, steps: 6)
                swipe(at: editorPoint, dx: -15, dy: 0, steps: 6)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let ignoredOK = appState.sidebarTab == .tasks
                    print("OPEN-MEASURE vertical+editor swipes ignored: tab=\(appState.sidebarTab.title) ok=\(ignoredOK)")
                    SelfTest.loggingScrollEvents = false

                    // Simulate hovering the sidebar tab title: warp the
                    // cursor onto it and post mouse-moved events so
                    // SwiftUI's onHover fires. The point comes from the
                    // fixed layout (see OBFTheme): the sidebar's tab title
                    // is centered in the bottom bar.
                    let hoverPoint = NSPoint(x: 924 + 130, y: 40)
                    let restore = CGEvent(source: nil)?.location
                    let screenRect = window.convertToScreen(CGRect(origin: hoverPoint, size: .zero))
                    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
                    CGWarpMouseCursorPosition(CGPoint(x: screenRect.origin.x, y: mainHeight - screenRect.origin.y))
                    if let moved = NSEvent.mouseEvent(
                        with: .mouseMoved,
                        location: hoverPoint,
                        modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 0,
                        pressure: 0
                    ) {
                        NSApplication.shared.postEvent(moved, atStart: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NSApplication.shared.postEvent(moved, atStart: false)
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        snap(window, "2_hover_tablist")
                        appState.sidebarTab = .tasks
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            snap(window, "3_empty_tab")
                            if let restore {
                                CGWarpMouseCursorPosition(restore)
                            }
                            // Visual check of task rendering and the
                            // "Задания" tab: swap in a demo document, wait
                            // for the debounced refresh that rebuilds the
                            // sidebar lists, snap, then restore the original
                            // and save it back immediately.
                            guard let storage = textView.textStorage else { exit(1) }
                            let original = storage.string
                            storage.setAttributedString(coordinator.render(markdown: """
                                # Проект OneBigFile
                                ## Раздел первый
                                Обычный текст перед заданием
                                - [ ] <!-- 2026-09-20 --> Купить молоко и хлеб
                                - [x] <!-- 2026-09-19 --> Сдать лабораторную работу
                                - [ ] <!-- 2026-09-21 --> Очень длинное задание, которое точно не влезет в одну строку редактора и должно перенестись на следующую строку с отступом — и ещё одно предложение для длины, и ещё одно, и ещё, и ещё одно, и ещё немного текста, чтобы в карточке точно было больше восьми строк и появился скролл
                                Обычный текст после задания
                                """))
                            // Mid-animation snapshot (~0.2 s after the
                            // debounced refresh starts the insertion
                            // transition), then the settled state.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                snap(window, "4a_tasks_animating")
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                snap(window, "4_tasks")
                                // Expand the first card: it grows into
                                // the capped, scrollable box. Synthetic
                                // clicks don't reliably reach SwiftUI tap
                                // gestures, so the test drives the same
                                // AppState flag the tap toggles.
                                appState.expandedTaskID = appState.tasks.first?.id
                                /// Deepest-first search for a view of the
                                /// given type in the hierarchy.
                                func findView<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
                                    for sub in view.subviews.reversed() {
                                        if let hit = sub as? T { return hit }
                                        if let hit = findView(type, in: sub) { return hit }
                                    }
                                    return nil
                                }
                                /// A synthetic scroll-wheel NSEvent built
                                /// from a CGEvent. Posted scroll events
                                /// never reach the view hierarchy (their
                                /// window is nil), so the test calls
                                /// scrollWheel(with:) directly.
                                func scrollEvent(dy: Int32, phase: Int64 = 2) -> NSEvent? {
                                    guard let source = CGEventSource(stateID: .hidSystemState),
                                          let cg = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                                           wheelCount: 2, wheel1: dy, wheel2: 0, wheel3: 0)
                                    else { return nil }
                                    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                                    return NSEvent(cgEvent: cg)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    snap(window, "5_expanded_task")
                                    // Scroll the expanded card's text box:
                                    // the text must move while the sidebar
                                    // list stays put — at both edges too.
                                    if let trap = findView(TrappedScrollView.self, in: content) {
                                        var outer: NSScrollView?
                                        var ancestor = trap.superview
                                        while let view = ancestor {
                                            if let sv = view as? NSScrollView { outer = sv; break }
                                            ancestor = view.superview
                                        }
                                        func scroll(_ dy: Int32, _ times: Int) {
                                            if let began = scrollEvent(dy: 0, phase: 1) { trap.scrollWheel(with: began) }
                                            for _ in 0..<times {
                                                if let event = scrollEvent(dy: dy) { trap.scrollWheel(with: event) }
                                            }
                                            if let ended = scrollEvent(dy: 0, phase: 4) { trap.scrollWheel(with: ended) }
                                        }
                                        scroll(30, 8)
                                        let offAfterDown = trap.contentView.bounds.origin.y
                                        scroll(30, 40) // reach the bottom edge
                                        let sidebarBefore = outer?.contentView.bounds.origin ?? .zero
                                        scroll(30, 8)  // at the edge: must not leak to the sidebar
                                        let leakDown = (outer?.contentView.bounds.origin ?? .zero) != sidebarBefore
                                        scroll(-30, 60)  // back to the top edge
                                        let atTop = trap.contentView.bounds.origin.y
                                        scroll(-30, 8)
                                        let leakUp = (outer?.contentView.bounds.origin ?? .zero) != sidebarBefore
                                        let trapOK = offAfterDown > 0 && atTop <= 0.5 && !leakDown && !leakUp
                                        print("OPEN-MEASURE trapped-scroll: docH=\(trap.documentView?.frame.height ?? -1) clipH=\(trap.contentView.bounds.height) moved=\(offAfterDown) top=\(atTop) leakDown=\(leakDown) leakUp=\(leakUp) ok=\(trapOK)")
                                        scroll(30, 4) // leave it visibly scrolled for the snapshot
                                    } else {
                                        print("OPEN-MEASURE trapped-scroll: TrappedScrollView not found ok=false")
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        snap(window, "6_expanded_scrolled")
                                        appState.expandedTaskID = nil
                                        snapTaskModals(window) {
                                        // Typing in a task: its card
                                        // switches to the wiggling
                                        // "Печатаем задание" state.
                                        if let firstTask = appState.tasks.first {
                                            textView.setSelectedRange(NSRange(location: firstTask.range.location + 1, length: 0))
                                            textView.insertText("…", replacementRange: textView.selectedRange())
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            snap(window, "7_typing_task")
                                            // Bug repro: Enter from inside
                                            // the task, Cmd+3 on the new
                                            // line, type — only the NEW
                                            // card may wiggle.
                                            if let firstTask = appState.tasks.first {
                                                textView.setSelectedRange(NSRange(location: NSMaxRange(firstTask.range) - 1, length: 0))
                                            }
                                            textView.insertNewline(nil)
                                            coordinator.toggleTask()
                                            textView.insertText("абв", replacementRange: textView.selectedRange())
                                            // Let the debounced refresh
                                            // create the new card, then
                                            // keep typing so the snapshot
                                            // catches it wiggling while
                                            // the old card stays still.
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                                textView.insertText("г", replacementRange: textView.selectedRange())
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    snap(window, "8_enter_cmd3_typing")
                                                    storage.setAttributedString(coordinator.render(markdown: original))
                                                    // The demo refresh
                                                    // saved the demo to
                                                    // disk; write the
                                                    // original back.
                                                    coordinator.saveNow()
                                                    sv.contentView.scroll(to: NSPoint(x: 0, y: 120))
                                                    sv.reflectScrolledClipView(sv.contentView)
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                        measure("after-scroll")
                                                        _ = content
                                                        exit(0)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Two-finger horizontal swipes switch sidebar tabs: fingers left →
    /// next, right → prev, at most one switch per gesture; mostly-vertical
    /// scrolling and short drags never trigger.
    private static func scenarioI() -> Bool {
        var recognizer = HorizontalSwipeRecognizer()

        func gesture(_ dx: CGFloat, _ dy: CGFloat, steps: Int) -> [SidebarTabMove] {
            var moves: [SidebarTabMove] = []
            if let move = recognizer.handle(phase: .began, deltaX: 0, deltaY: 0) { moves.append(move) }
            for _ in 0..<steps {
                if let move = recognizer.handle(phase: .changed, deltaX: dx, deltaY: dy) { moves.append(move) }
            }
            if let move = recognizer.handle(phase: .ended, deltaX: 0, deltaY: 0) { moves.append(move) }
            return moves
        }

        let left = gesture(-12, 2, steps: 8)       // -96 horizontal: next
        let right = gesture(12, -2, steps: 8)      // +96 horizontal: prev
        let vertical = gesture(2, -12, steps: 8)   // vertical-dominant: none
        let short = gesture(-5, 0, steps: 5)       // -25 < threshold: none

        print("    left=\(left) right=\(right) vertical=\(vertical) short=\(short)")
        let ok = left == [.next] && right == [.prev] && vertical.isEmpty && short.isEmpty
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+3 on an empty line inserts the checkbox immediately; typing goes
    /// after it; Enter ends the task and continues in plain body text.
    /// Serialization stores the paragraph as a markdown task.
    private static func scenarioJ() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        coordinator.toggleTask()
        let checkboxThere = storage.string == "\u{FFFC}"
            && storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 1
            && storage.attribute(.attachment, at: 0, effectiveRange: nil) != nil

        type(textView, "текст задания")
        textView.insertNewline(nil)
        type(textView, "обычный текст")
        pump()

        let markers = paragraphMarkers(storage)
        let serialized = coordinator.serialize(storage: storage)
        // Tasks created via Cmd+3 carry today's date as a hidden comment.
        let expected = "- [ ] <!-- \(Self.todayString()) --> текст задания\nобычный текст"
        print("    checkbox=\(checkboxThere) markers=\(markers) serialized=\(serialized.debugDescription)")
        let ok = checkboxThere && markers == ["task", "body"] && serialized == expected
        print("    -> OK: \(ok)")
        return ok
    }

    /// Cmd+4 marks the task under the caret done (checkmark, dimmed text,
    /// "- [x]" on save) and toggles back on a second press.
    private static func scenarioK() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "сделать дело")
        coordinator.toggleTask()
        coordinator.toggleTaskDone()
        pump()

        let markedDone = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 2
        let color = storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        let dimmed = color != nil && color!.alphaComponent < 0.6
        let serialized = coordinator.serialize(storage: storage)

        coordinator.toggleTaskDone()
        pump()
        let backToTodo = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) as? Int == 1

        print("    done=\(markedDone) dimmed=\(dimmed) serialized=\(serialized.debugDescription) backToTodo=\(backToTodo)")
        let ok = markedDone && dimmed && serialized == "- [x] <!-- \(Self.todayString()) --> сделать дело" && backToTodo
        print("    -> OK: \(ok)")
        return ok
    }

    /// Backspace with the caret immediately after the checkbox removes the
    /// task formatting but keeps the text.
    private static func scenarioL() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()

        type(textView, "текст задания")
        coordinator.toggleTask()
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.deleteBackward(nil)
        pump()

        let untasked = storage.attribute(.obfTaskState, at: 0, effectiveRange: nil) == nil
        let textKept = storage.string == "текст задания"
        print("    untasked=\(untasked) text=\(storage.string.debugDescription)")
        let ok = untasked && textKept
        print("    -> OK: \(ok)")
        return ok
    }

    /// Markdown round-trip: headings, tasks (todo and done), plain bullets
    /// and body text parse and serialize back to the identical string.
    private static func scenarioM() -> Bool {
        let (_, _, coordinator, storage) = makeStack()

        let markdown = "# Заголовок\n- [ ] сделать раз\n- [x] сделано два\n- просто пункт\nобычный текст"
        storage.setAttributedString(coordinator.render(markdown: markdown))
        let serialized = coordinator.serialize(storage: storage)
        print("    roundtrip=\(serialized == markdown)")
        if serialized != markdown {
            print("    got: \(serialized.debugDescription)")
        }
        let ok = serialized == markdown
        print("    -> OK: \(ok)")
        return ok
    }

    /// A task's wrapped lines align with the text after the checkbox (the
    /// hanging indent equals the checkbox width including its gap).
    private static func scenarioN() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return false }

        coordinator.toggleTask()
        let longLine = (0..<60).map { _ in "слово" }.joined(separator: " ")
        type(textView, longLine)
        textView.setFrameSize(NSSize(width: 892, height: 400))
        layoutManager.ensureLayout(for: container)

        var lineStarts: [CGFloat] = []
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { rect, _, _, glyphRange, _ in
            let location = layoutManager.location(forGlyphAt: glyphRange.location)
            lineStarts.append(rect.minX + location.x)
        }
        let indent = ceil(appState.bodyFont.pointSize * 0.85) + 6
        let padding = container.lineFragmentPadding
        print("    lineStarts=\(lineStarts) indent=\(indent) padding=\(padding)")
        let ok = lineStarts.count > 1
            && abs(lineStarts[0] - padding) < 0.5
            && lineStarts.dropFirst().allSatisfy { abs($0 - padding - indent) < 0.5 }
        print("    -> OK: \(ok)")
        return ok
    }

    /// The "Задания" sidebar tab: dated tasks round-trip through markdown
    /// with their hidden comment, the list is grouped active-then-done with
    /// the newest on top of each group, and a task knows the headings above
    /// it. A task created via Cmd+3 gets today's date.
    private static func scenarioO() -> Bool {
        let (appState, _, coordinator, storage) = makeStack()

        let markdown = """
        # Проект
        ## Первая часть
        - [ ] <!-- 2026-09-20 --> старое задание
        - [ ] <!-- 2026-09-21 --> новое задание
        - [x] <!-- 2026-09-19 --> выполненное задание
        ## Вторая часть
        - [ ] задание без даты
        """
        storage.setAttributedString(coordinator.render(markdown: markdown))
        // Save + reload: rebuilds the sidebar data from a fresh render.
        coordinator.saveNow()
        coordinator.loadDocument()

        let roundTrip = coordinator.serialize(storage: storage) == markdown
        let tasks = appState.tasks
        for task in tasks {
            print("    task text=\(task.text.debugDescription) done=\(task.done) created=\(task.created ?? "nil") h1=\(task.h1 ?? "nil") h2=\(task.h2 ?? "nil")")
        }

        let countOk = tasks.count == 4
        // Active newest-first, then done newest-first; dateless tasks sink
        // to the bottom of their group.
        let orderOk = countOk
            && tasks.map(\.text) == ["новое задание", "старое задание", "задание без даты", "выполненное задание"]
            && tasks[3].done
        let datesOk = countOk
            && tasks[0].created == "2026-09-21"
            && tasks[1].created == "2026-09-20"
            && tasks[2].created == nil
            && tasks[3].created == "2026-09-19"
        let pathsOk = countOk
            && tasks[0].h1 == "Проект" && tasks[0].h2 == "Первая часть"
            && tasks[2].h1 == "Проект" && tasks[2].h2 == "Вторая часть"

        // A fresh Cmd+3 task gets today's date, serialized as a comment.
        let (_, textView2, coordinator2, storage2) = makeStack()
        type(textView2, "свежее задание")
        coordinator2.toggleTask()
        pump()
        let created = storage2.attribute(.obfTaskCreated, at: 0, effectiveRange: nil) as? String
        let serialized2 = coordinator2.serialize(storage: storage2)
        let todayOk = created == Self.todayString()
            && serialized2 == "- [ ] <!-- \(Self.todayString()) --> свежее задание"

        print("    roundTrip=\(roundTrip) order=\(orderOk) dates=\(datesOk) paths=\(pathsOk) today=\(todayOk)")
        let ok = roundTrip && orderOk && datesOk && pathsOk && todayOk
        print("    -> OK: \(ok)")
        return ok
    }

    /// Sidebar card identity (uid) survives edits above the task and a
    /// done-toggle: only position/state change, so the sidebar animates the
    /// existing card instead of re-creating it.
    private static func scenarioP() -> Bool {
        let (appState, textView, coordinator, storage) = makeStack()

        storage.setAttributedString(coordinator.render(markdown: """
        # Проект
        текст
        - [ ] <!-- 2026-09-20 --> первое
        - [ ] <!-- 2026-09-21 --> второе
        """))
        coordinator.saveNow()
        coordinator.loadDocument()

        let before = appState.tasks
        let countOk = before.count == 2

        // An edit in the body line above the tasks shifts their ranges by
        // 3 without touching headings or task content; identities must not
        // change, otherwise the sidebar would re-animate both cards.
        let bodyLine = "# Проект".count + 1
        textView.setSelectedRange(NSRange(location: bodyLine, length: 0))
        type(textView, "xxx")
        pump()
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterEdit = appState.tasks
        let uidsStable = countOk && afterEdit.map(\.uid) == before.map(\.uid)
        let rangesShifted = countOk && afterEdit.count == 2
            && zip(before, afterEdit).allSatisfy {
                $1.range.location == $0.range.location + 3
            }

        // Typing inside a task marks its card as "being typed" and the
        // card keeps its identity across the rebuild (no re-creation).
        let typedTask = afterEdit[0]
        textView.setSelectedRange(NSRange(location: typedTask.range.location + 1, length: 0))
        type(textView, "yy")
        pump()
        let hintOk = appState.editingTaskLocation == typedTask.range.location
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterTyping = appState.tasks
        let typedUidStable = hintOk
            && afterTyping.first?.uid == typedTask.uid
            && afterTyping.first?.text == "yyвторое"

        // Cmd+4 flips done: the card keeps its uid and moves to the done
        // group at the end of the list.
        let toggledUID = afterTyping.first?.uid
        if let first = afterTyping.first {
            textView.setSelectedRange(NSRange(location: first.range.location, length: 0))
        }
        coordinator.toggleTaskDone()
        pump()
        coordinator.saveNow()
        coordinator.loadDocument()

        let afterToggle = appState.tasks
        let moved = toggledUID != nil
            && afterToggle.count == 2
            && afterToggle.last?.uid == toggledUID
            && afterToggle.last?.done == true

        print("    count=\(countOk) uidsStable=\(uidsStable) shifted=\(rangesShifted) hint=\(hintOk) typedUid=\(typedUidStable) moved=\(moved)")
        let ok = countOk && uidsStable && rangesShifted && typedUidStable && moved
        print("    -> OK: \(ok)")
        return ok
    }

    /// Expanded task text: never shorter than the collapsed two-line box,
    /// grows with the text, and stops at the eight-line cap — longer texts
    /// scroll inside the box.
    private static func scenarioQ() -> Bool {
        let words = "строка текста задания "
        let short = TaskCardView.expandedHeight(for: "короткое")
        let mid = TaskCardView.expandedHeight(for: String(repeating: words, count: 4))
        let long = TaskCardView.expandedHeight(for: String(repeating: words, count: 40))
        let longer = TaskCardView.expandedHeight(for: String(repeating: words, count: 80))

        let ok = mid > short && long > mid && longer == long
        print("    short=\(short) mid=\(mid) long=\(long) longer=\(longer)")
        print("    -> OK: \(ok)")
        return ok
    }

    /// Enter from inside a task moves the caret to a new plain line, so
    /// the OLD task's card must leave the typing state; after Cmd+3 on the
    /// new line only the NEW task is marked as being typed.
    private static func scenarioR() -> Bool {
        let (appState, textView, coordinator, _) = makeStack()

        coordinator.toggleTask()
        type(textView, "первое")
        pump()
        let typingA = appState.editingTaskLocation == 0

        textView.insertNewline(nil)
        pump()
        let clearedAfterEnter = appState.editingTaskLocation == nil

        coordinator.toggleTask()
        pump()
        let newLocation = appState.editingTaskLocation
        let markedNew = newLocation != nil && newLocation != 0

        type(textView, "второе")
        pump()
        let staysNew = appState.editingTaskLocation == newLocation

        print("    typingA=\(typingA) clearedAfterEnter=\(clearedAfterEnter) markedNew=\(markedNew) staysNew=\(staysNew)")
        let ok = typingA && clearedAfterEnter && markedNew && staysNew
        print("    -> OK: \(ok)")
        return ok
    }

    /// The expanded task text box (TrappedScrollView) lets a scroll event
    /// through only while its content can still move in the event's
    /// direction; at the edges the event is eaten, so the sidebar's scroll
    /// view never starts scrolling while the pointer is inside the box.
    private static func scenarioY() -> Bool {
        let state = makeRoutineState()
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            if !cond { print("    FAIL: \(label)"); ok = false }
        }
        let wasVisible = state.sidebarVisible
        state.setSidebarVisible(true)
        state.sidebarTab = .tasks
        state.toggleSidebar()
        check(!state.sidebarVisible, "Cmd+S hides")
        state.toggleSidebar()
        check(state.sidebarVisible && state.sidebarTab == .tasks, "reopens on the same tab")
        state.toggleSidebar()
        state.showRoutine(day: nil)
        check(state.sidebarVisible && state.sidebarTab == .routine, "Cmd+R reveals the sidebar")
        // Structure folding: only H1s with H2s fold; folded H2s drop out.
        func item(_ title: String, _ level: Int, _ at: Int) -> OutlineItem {
            OutlineItem(title: title, level: level, range: NSRange(location: at, length: 1))
        }
        let foldsWere = state.collapsedOutline
        state.collapsedOutline = []
        state.outline = [item("A", 1, 0), item("a1", 2, 10), item("a2", 2, 20), item("B", 1, 30), item("C", 1, 40), item("c1", 2, 50)]
        check(state.foldableOutlineIDs == [0, 40], "foldable: H1 with H2 only")
        state.toggleOutlineFold(state.outline[0])
        check(state.visibleOutline.map(\.title) == ["A", "B", "C", "c1"], "A folded")
        state.toggleOutlineFold(state.outline[4])
        check(state.visibleOutline.map(\.title) == ["A", "B", "C"], "C folded too")
        state.toggleOutlineFold(state.outline[0])
        check(state.visibleOutline.map(\.title) == ["A", "a1", "a2", "B", "C"], "A unfolded")
        state.collapsedOutline = foldsWere
        let crumbWas = state.showBreadcrumb
        state.breadcrumb = Breadcrumb(h1: OutlineItem(title: "A", level: 1, range: NSRange(location: 0, length: 1)))
        state.showBreadcrumb = false
        check(UserDefaults.standard.bool(forKey: "showBreadcrumb") == false, "breadcrumb switch persisted")
        state.showBreadcrumb = crumbWas
        state.setSidebarVisible(wasVisible)
        print("    ok=\(ok)")
        return ok
    }

    private static func scenarioX() -> Bool {
        let (_, textView, coordinator, storage) = makeStack()
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            if !cond { print("    FAIL: \(label)"); ok = false }
        }
        let markdown = """
            # Предмет
            - пункт первого уровня
            \t- вложенный пункт с длинным текстом, который переносится на следующую строку и должен висеть под текстом, а не под маркером
            \t\t- третий уровень
            Ссылка на курс:
            \thttps://e-learning.bmstu.ru/iu5/mod/folder/view.php?id=1343
            -не пункт (без пробела)
            - [ ] <!-- 2026-09-25 --> задание
            """
        storage.setAttributedString(coordinator.render(markdown: markdown))
        coordinator.debugApplyStyles()
        pump()
        let ns = storage.string as NSString
        func paragraph(_ prefix: String) -> NSRange {
            var found = NSRange(location: NSNotFound, length: 0)
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { sub, range, _, stop in
                if sub?.hasPrefix(prefix) == true { found = range; stop.pointee = true }
            }
            return found
        }
        func bullet(_ prefix: String) -> String? {
            let range = paragraph(prefix)
            let dash = ns.range(of: "-", range: range).location
            return dash == NSNotFound ? nil : storage.attribute(.obfBullet, at: dash, effectiveRange: nil) as? String
        }
        func headIndent(_ prefix: String) -> CGFloat {
            (storage.attribute(.paragraphStyle, at: paragraph(prefix).location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? -1
        }
        check(bullet("- пункт") == "•" && bullet("\t- вложенный") == "◦" && bullet("\t\t- третий") == "▪", "bullets by level")
        check(bullet("-не пункт") == nil, "no bullet without space")
        check(headIndent("\t- вложенный") > Coordinator.indentStep && headIndent("\t- вложенный") < Coordinator.indentStep * 2,
              "hanging indent under the text: \(headIndent("\t- вложенный"))")
        check(headIndent("\thttps") == Coordinator.indentStep, "tab-indented line keeps its indent")
        let link = ns.range(of: "https://")
        check((storage.attribute(.obfLink, at: link.location, effectiveRange: nil) as? URL)?.host == "e-learning.bmstu.ru",
              "link detected")
        // The bullet is drawn as a glyph swap only: the characters stay "- ".
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            lm.ensureLayout(for: tc)
            let dash = ns.range(of: "-", range: paragraph("- пункт")).location
            let glyph = lm.cgGlyph(at: lm.glyphIndexForCharacter(at: dash))
            let font = storage.attribute(.font, at: dash, effectiveRange: nil) as! NSFont
            var chars = Array("•".utf16)
            var expected = CGGlyph(0)
            CTFontGetGlyphsForCharacters(font as CTFont, &chars, &expected, 1)
            check(glyph == expected && expected != 0, "bullet glyph drawn")
        }
        check(coordinator.serialize(storage: storage) == markdown, "markdown round-trip unchanged")

        // Cmd+5: an empty line becomes an item with the caret after "- ".
        storage.setAttributedString(coordinator.render(markdown: "# Заголовок\n\n"))
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        coordinator.toggleList()
        type(textView, "пункт")
        check(coordinator.serialize(storage: storage) == "# Заголовок\n- пункт", "cmd+5 on empty line: \(coordinator.serialize(storage: storage).debugDescription)")
        // Several lines at once, tabs kept; a heading in the selection is skipped.
        storage.setAttributedString(coordinator.render(markdown: "# Заголовок\nодин\n\tдва\n- три"))
        textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        coordinator.toggleList()
        check(coordinator.serialize(storage: storage) == "# Заголовок\n- один\n\t- два\n- три", "cmd+5 adds to plain lines")
        textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        coordinator.toggleList()
        check(coordinator.serialize(storage: storage) == "# Заголовок\nодин\n\tдва\nтри", "cmd+5 again removes")
        // The caret stays on its word.
        storage.setAttributedString(coordinator.render(markdown: "слово"))
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.toggleList()
        check(textView.selectedRange().location == 5, "caret shifted with the marker")
        coordinator.toggleList()
        check(textView.selectedRange().location == 3 && storage.string == "слово", "caret back after removal")
        print("    ok=\(ok)")
        return ok
    }

    private static func scenarioT() -> Bool {
        let short = !TaskCardView.needsExpansion("Купить молоко")
        let two = !TaskCardView.needsExpansion("Если задание слишком короткое")
        let long = TaskCardView.needsExpansion(String(repeating: "Очень длинное задание ", count: 6))
        let ok = short && two && long
        print("    short=\(short) twoLines=\(two) long=\(long)")
        print("    -> OK: \(ok)")
        return ok
    }

    private static func scenarioS() -> Bool {
        let max: CGFloat = 432
        var ok = true
        // Both natural-scrolling settings: at the top, only toward-bottom
        // events may pass; at the bottom, only toward-top.
        for inverted in [false, true] {
            let bottomDelta: CGFloat = inverted ? -10 : 10
            ok = ok && TrappedScrollView.shouldScroll(offset: 0, maxOffset: max, deltaY: bottomDelta, inverted: inverted)
            ok = ok && !TrappedScrollView.shouldScroll(offset: 0, maxOffset: max, deltaY: -bottomDelta, inverted: inverted)
            ok = ok && !TrappedScrollView.shouldScroll(offset: max, maxOffset: max, deltaY: bottomDelta, inverted: inverted)
            ok = ok && TrappedScrollView.shouldScroll(offset: max, maxOffset: max, deltaY: -bottomDelta, inverted: inverted)
            // Mid-scroll: both directions pass.
            ok = ok && TrappedScrollView.shouldScroll(offset: max / 2, maxOffset: max, deltaY: bottomDelta, inverted: inverted)
            ok = ok && TrappedScrollView.shouldScroll(offset: max / 2, maxOffset: max, deltaY: -bottomDelta, inverted: inverted)
        }
        // Content fits without scrolling: nothing passes.
        ok = ok && !TrappedScrollView.shouldScroll(offset: 0, maxOffset: 0, deltaY: 10, inverted: true)
            && !TrappedScrollView.shouldScroll(offset: 0, maxOffset: 0, deltaY: -10, inverted: true)

        print("    -> OK: \(ok)")
        return ok
    }

    /// Drives the REAL app window (SwiftUI stack included) through the
    /// ghost-line scenario and saves screen captures to /tmp. Launched with
    /// --replay-bug2; exits the process when done.
    static func replayBug2(appState: AppState) {
        func log(_ s: String) {
            fputs(s + "\n", stderr)
            let line = (s + "\n").data(using: .utf8)!
            if let fh = FileHandle(forWritingAtPath: "/tmp/obf_replay_log") {
                fh.seekToEndOfFile()
                fh.write(line)
                try? fh.close()
            } else {
                try? line.write(to: URL(fileURLWithPath: "/tmp/obf_replay_log"))
            }
        }
        log("replayBug2: entry editor=\(appState.editor != nil)")
        guard let coordinator = appState.editor as? Coordinator,
              let textView = coordinator.debugTextView,
              let window = textView.window else {
            log("replayBug2: EARLY RETURN (coordinator/textView/window missing)")
            return
        }
        let app = NSApplication.shared
        let storage = textView.textStorage!

        /// Copies what is currently on screen without triggering a redraw.
        func snap(_ name: String) {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.bestResolution]
            ) else {
                print("snap \(name): CAPTURE FAILED")
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let pngType = NSBitmapImageRep.FileType.png
            if let data = rep.representation(using: pngType, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_snap_\(name).png"))
            }
            let markers = paragraphMarkers(storage)
            log("snap \(name): sel=\(textView.selectedRange()) storage=\(storage.string.debugDescription) markers=\(markers)")
        }

        func keyEvent(_ characters: String, _ keyCode: UInt16) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        }

        /// Sends a key event synchronously (no run-loop turn in between) and
        /// captures the backing store before and after the next display
        /// pass, so a single-frame ghost cannot slip between snapshots.
        func sendAndCapture(_ characters: String, _ keyCode: UInt16, _ name: String) {
            guard let event = keyEvent(characters, keyCode) else { return }
            app.sendEvent(event)
            snap("\(name)_pre")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.06))
            snap("\(name)_post")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Setup: H1, H2, two blank lines, one word.
            textView.insertText(
                "Заголовок\nПодзадача\n\n\ntекст",
                replacementRange: NSRange(location: 0, length: storage.length)
            )
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator.setHeadingLevel(1)
            textView.setSelectedRange(NSRange(location: 10, length: 0))
            coordinator.setHeadingLevel(2)
            snap("S0_setup")
            // Empty the H1 by holding Backspace from its end (9 chars) —
            // rapid repeats, like the user does.
            textView.setSelectedRange(NSRange(location: 9, length: 0))
            for i in 1...9 {
                sendAndCapture("\u{7F}", 51, "E\(i)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // Now "\nПодзадача\n\n\ntекст"; caret onto "текст" (loc 13) and
            // delete the blank lines above it, still hold-speed.
            textView.setSelectedRange(NSRange(location: 13, length: 0))
            snap("S1_caret_on_word")
            sendAndCapture("\u{7F}", 51, "D1")
            sendAndCapture("\u{7F}", 51, "D2")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            snap("S2_settled")
            log("REPLAY DONE storage=\(storage.string.debugDescription)")
            exit(0)
        }
    }

    /// Real-window repro for the "select text, type over it" hang/crash that
    /// only surfaces through the genuine event/drawing path. Builds the same
    /// view stack as EditorView, orders a window front, then posts actual
    /// key-down events through NSApplication. A watchdog exits 0 on success;
    /// if the main thread spins or the app crashes, the parent alarm kills
    /// the process (detected by the caller).
    static func runUITest() -> Int32 {
        let report = #selector(NSApplication.reportException)
        if let original = class_getInstanceMethod(NSApplication.self, report),
           let replacement = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.obf_reportException)) {
            method_exchangeImplementations(original, replacement)
        }
        NSSetUncaughtExceptionHandler { exception in
            print("EXCEPTION: \(exception.name) — \(exception.reason ?? "nil")")
            for line in exception.callStackSymbols.prefix(25) {
                print("    \(line)")
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appState = AppState()
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.backgroundColor = OBFTheme.bgNS
        textView.drawsBackground = true
        textView.insertionPointColor = OBFTheme.textNS
        textView.selectedTextAttributes = [
            .backgroundColor: OBFTheme.selectionNS,
            .foregroundColor: OBFTheme.textNS
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = OBFTheme.bgNS
        scrollView.borderType = .noBorder

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        appState.editor = coordinator
        coordinator.loadDocument()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        // Replace the document with deterministic content (the real file is
        // restored by the caller afterwards).
        textView.insertText(
            "Первая строка текста\nВторая строка текста\nТретья строка текста",
            replacementRange: NSRange(location: 0, length: storage.length)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let sel = textView.selectedRange()
            let ok = sel == NSRange(location: 3, length: 0)
                && storage.string == "xyz"
                && !SelfTest.uiExceptionSeen
            print("UITEST \(ok ? "OK" : "FAILED") sel=\(sel) storage=\(storage.string.debugDescription) exceptions=\(SelfTest.uiExceptionSeen)")
            exit(ok ? 0 : 1)
        }

        func postKey(_ characters: String, _ ignoring: String, _ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            app.postEvent(event, atStart: false)
        }

        // Give the window a moment to become key, then: select all, type over
        // the selection — the exact user repro.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("sel before cmd+A: \(textView.selectedRange())")
            postKey("\u{1}", "a", .command, 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("sel after cmd+A: \(textView.selectedRange())")
            postKey("x", "x", [], 7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("after typing x, sel=\(textView.selectedRange())")
            postKey("y", "y", [], 16)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            postKey("z", "z", [], 6)
        }

        app.run()
        return 0
    }
}

extension NSApplication {
    /// Swizzled over `reportException:` during --uitest to log exceptions
    /// that AppKit would otherwise only print a one-line warning for.
    @objc func obf_reportException(_ exception: NSException) {
        SelfTest.uiExceptionSeen = true
        print("REPORTED EXCEPTION: \(exception.name) — \(exception.reason ?? "nil")")
        for line in exception.callStackSymbols.prefix(30) {
            print("    \(line)")
        }
        // Original implementation (implementations were exchanged).
        obf_reportException(exception)
    }
}

extension SelfTest {
    /// Set by the swizzled reportException: during --uitest.
    static var uiExceptionSeen = false

    /// When true, the sidebar scroll monitor logs every scrollWheel event
    /// it sees — lets --uitest-open verify the gesture pipeline.
    static var loggingScrollEvents = false
    static var debugScrollLog: [String] = []

    /// Ghost-line repro: after deleting an H1, deleting the blank lines
    /// above a word leaves the word's old line on screen (drawn twice).
    /// Drives the real event path and captures the on-screen backing store
    /// (cacheDisplay performs NO redraw) right after the edit and after the
    /// debounced refresh, saving PNGs to /tmp for inspection.
    static func runUITestBug2() -> Int32 {
        let report = #selector(NSApplication.reportException)
        if let original = class_getInstanceMethod(NSApplication.self, report),
           let replacement = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.obf_reportException)) {
            method_exchangeImplementations(original, replacement)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appState = AppState()
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let textView = OBFTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 500), textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = appState.bodyFont
        textView.textColor = OBFTheme.textNS
        textView.backgroundColor = OBFTheme.bgNS
        textView.drawsBackground = true
        textView.insertionPointColor = OBFTheme.textNS
        textView.selectedTextAttributes = [
            .backgroundColor: OBFTheme.selectionNS,
            .foregroundColor: OBFTheme.textNS
        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = OBFTheme.bgNS
        scrollView.borderType = .noBorder

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        let coordinator = Coordinator(appState: appState)
        coordinator.attach(textView: textView)
        appState.editor = coordinator
        coordinator.loadDocument()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        app.activate(ignoringOtherApps: true)
        // Prime the backing store so cacheDisplay has real content later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            window.display()
        }

        // Deterministic setup: H1, H2, two blank lines, one word.
        textView.insertText(
            "Заголовок\nПодзадача\n\n\ntекст",
            replacementRange: NSRange(location: 0, length: storage.length)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.setHeadingLevel(1)
        textView.setSelectedRange(NSRange(location: 10, length: 0))
        coordinator.setHeadingLevel(2)
        textView.setSelectedRange(NSRange(location: storage.length, length: 0))

        /// Posts a key event; function-key characters get the .function
        /// modifier, which AppKit expects for arrows/Home/End.
        func postKey(_ characters: String, _ modifiers: NSEvent.ModifierFlags, _ keyCode: UInt16, delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var flags = modifiers
                let code = characters.unicodeScalars.first?.value ?? 0
                if code >= 0xF700 && code <= 0xF8FF {
                    flags.insert(.function)
                }
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                ) else { return }
                app.postEvent(event, atStart: false)
            }
        }

        /// Copies what is currently on screen without triggering a redraw.
        func snap(_ name: String) {
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(window.windowNumber),
                [.bestResolution]
            ) else {
                print("snap \(name): CAPTURE FAILED")
                return
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let pngType = NSBitmapImageRep.FileType.png
            if let data = rep.representation(using: pngType, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/obf_snap_\(name).png"))
            }
            print("snap \(name): sel=\(textView.selectedRange()) storage=\(storage.string.debugDescription)")
            if let lm = textView.layoutManager, let tc = textView.textContainer {
                lm.ensureLayout(for: tc)
                var fragmentHeight: CGFloat = 0
                var fragments = 0
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in
                    fragments += 1
                }
                // measure used height via line fragment rects
                var y: CGFloat = 0
                lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { rect, _, _, _, _ in
                    y = max(y, rect.maxY)
                }
                fragmentHeight = y
                let used = lm.usedRect(for: tc)
                print("    glyphs=\(lm.numberOfGlyphs)/chars=\(storage.length) fragments=\(fragments) maxY=\(fragmentHeight) usedH=\(used.height) frameH=\(textView.frame.height) boundsH=\(textView.bounds.height)")
            }
        }

        // t+0.3: baseline; select the whole H1 paragraph (text + newline)
        // and delete it with a real Backspace event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            snap("A_before")
            textView.setSelectedRange(NSRange(location: 0, length: 10))
            postKey("\u{7F}", [], 51, delay: 0.1)             // Backspace
        }
        // t+1.1: settled after H1 deletion; caret onto "текст".
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            snap("B_h1_deleted")
            textView.setSelectedRange(NSRange(location: 12, length: 0))
        }
        /// Sends a key event synchronously (no run-loop turn in between) and
        /// captures the backing store before and after the next display
        /// pass, so a single-frame ghost cannot slip between snapshots.
        func sendAndCapture(_ characters: String, _ keyCode: UInt16, _ name: String) {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) else { return }
            app.sendEvent(event)
            snap("\(name)_1_pre_draw")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
            snap("\(name)_2_post_draw")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.6))
            snap("\(name)_3_after_debounce")
        }

        // t+1.5: caret is on "текст"; delete the blank line above it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            snap("C_caret_on_word")
            textView.setSelectedRange(NSRange(location: 12, length: 0))
            sendAndCapture("\u{7F}", 51, "D_with_h1_deleted")
        }
        // t+4.0: control run — same edit WITHOUT the prior H1 deletion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            textView.insertText(
                "Подзадача\n\n\ntекст",
                replacementRange: NSRange(location: 0, length: storage.length)
            )
            textView.setSelectedRange(NSRange(location: 10, length: 0))
            coordinator.setHeadingLevel(2)
            textView.setSelectedRange(NSRange(location: 12, length: 0))
            snap("F_control_setup")
            sendAndCapture("\u{7F}", 51, "G_no_h1_deleted")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            print("BUG2 UITEST DONE storage=\(storage.string.debugDescription) exceptions=\(SelfTest.uiExceptionSeen)")
            exit(0)
        }

        app.run()
        return 0
    }
}
