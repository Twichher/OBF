import AppKit

/// Demo routine with made-up history, to see streaks at work. Launch with
/// `--demo-routine`: the app then runs on throwaway files in /tmp (the real
/// document and routine.json are never touched) and opens the routine tab.
/// `--uitest-demo` does the same and snapshots the tab to /tmp.
enum RoutineDemo {
    static let routineURL = URL(fileURLWithPath: "/tmp/obf_demo_routine.json")
    static let documentURL = URL(fileURLWithPath: "/tmp/obf_demo_document.md")

    static func makeAppState() -> AppState {
        let store = RoutineStore(fileURL: routineURL)
        store.save(data(today: RoutineDate.key(Date())))
        let state = AppState(store: DocumentStore(fileURL: documentURL), routineStore: store)
        state.showRoutine(day: nil)
        return state
    }

    /// Tasks relative to `today`, with done logs shaped to give known
    /// streaks (as long as today itself is not marked):
    /// - "Подъём в 8 утра", every day: 12 in a row.
    /// - "Чтение 30 минут", every day: 4 in a row + done today = 5.
    /// - "Пара …", Tue/Thu, Saturday added two weeks ago: ВТ-3 · ЧТ-5 · СБ-1.
    /// - "Зал …", Mon/Wed/Fri: ПН-3 · СР-2 · ПТ-0.
    /// - "Генеральная уборка", Sundays: ВС-4.
    /// - "1 час на улучшении One Big File", Thursdays: ЧТ-2.
    /// - "Статья по диплому", Thursdays, created today: no streak yet.
    static func data(today: String) -> RoutineData {
        func ago(_ days: Int) -> String { RoutineDate.adding(-days, to: today) }

        var tasks: [RoutineTask] = []

        var rise = task("Подъём в 8 утра", created: ago(40), [(ago(40), Set(0..<7))])
        rise.done = dailyLog(rise, today: today, streak: 12)
        tasks.append(rise)

        var reading = task("Чтение 30 минут", created: ago(20), [(ago(20), Set(0..<7))])
        reading.done = dailyLog(reading, today: today, streak: 4) + [today]
        tasks.append(reading)

        var lecture = task("Пара в 15:55 — Аналитические модели АСОИУ", created: ago(60),
                           [(ago(60), [1, 3]), (ago(14), [1, 3, 5])])
        lecture.done = weeklyLog(lecture, today: today, streaks: [1: 3, 3: 5, 5: 1])
        tasks.append(lecture)

        var gym = task("Зал с 9 утра до 10:30", created: ago(50), [(ago(50), [0, 2, 4])])
        gym.done = weeklyLog(gym, today: today, streaks: [0: 3, 2: 2, 4: 0])
        tasks.append(gym)

        var cleaning = task("Генеральная уборка", created: ago(45), [(ago(45), [6])])
        cleaning.done = weeklyLog(cleaning, today: today, streaks: [6: 4])
        tasks.append(cleaning)

        let weekday = RoutineDate.weekday(today)
        var app = task("1 час на улучшении One Big File", created: ago(30), [(ago(30), [weekday])])
        app.done = weeklyLog(app, today: today, streaks: [weekday: 2])
        tasks.append(app)

        tasks.append(task("Статья по диплому", created: today, [(today, [weekday])]))

        var study = task("1 час на обучении: линал, ангем, тервер, матстат", created: ago(120),
                         [(ago(120), [0, 1, 2, 3, 4, 5])])
        study.done = weeklyLog(study, today: today, streaks: [0: 12, 1: 14, 2: 11, 3: 15, 4: 10, 5: 13])
        tasks.append(study)

        // Every other Thursday-like task on today's weekday: one on this
        // week (streak ×3), one on its off week (dimmed, next date shown).
        let thisWeek = RoutineDate.weekStart(today)
        var biweeklyOn = task("Задача «А» — через неделю", created: ago(70), [])
        biweeklyOn.schedule = [RoutineScheduleEntry(
            from: ago(70), days: [weekday], everyWeeks: 2, anchor: RoutineDate.adding(-70, to: thisWeek))]
        biweeklyOn.done = weeklyLog(biweeklyOn, today: today, streaks: [weekday: 3])
        tasks.append(biweeklyOn)

        var biweeklyOff = task("Задача «Б» — через неделю, не на этой", created: ago(63), [])
        biweeklyOff.schedule = [RoutineScheduleEntry(
            from: ago(63), days: [weekday], everyWeeks: 2, anchor: RoutineDate.adding(-63, to: thisWeek))]
        biweeklyOff.done = weeklyLog(biweeklyOff, today: today, streaks: [weekday: 2])
        tasks.append(biweeklyOff)

        // OBF_DEMO_ONLY=<text prefix>: keep just the matching tasks (to
        // look at cards that would sit below the fold).
        if let only = ProcessInfo.processInfo.environment["OBF_DEMO_ONLY"] {
            tasks = tasks.filter { $0.text.hasPrefix(only) }
        }
        var data = RoutineData(tasks: tasks)
        data.normalizeOrder()
        return data
    }

    private static func task(_ text: String, created: String,
                             _ schedule: [(String, Set<Int>)]) -> RoutineTask {
        RoutineTask(text: text, created: created,
                    schedule: schedule.map { RoutineScheduleEntry(from: $0.0, days: $0.1) })
    }

    /// Done on the `streak` due days before today, missed the one before
    /// those, then done on three of every four due days back to creation.
    private static func dailyLog(_ task: RoutineTask, today: String, streak: Int) -> [String] {
        var log: [String] = []
        var date = RoutineDate.adding(-1, to: today)
        var index = 0
        while date >= task.created {
            if task.isScheduled(on: date) {
                if index < streak || (index > streak && index % 4 != 0) {
                    log.append(date)
                }
                index += 1
            }
            date = RoutineDate.adding(-1, to: date)
        }
        return log.sorted()
    }

    /// Per weekday: done on the last `count` due occurrences before today,
    /// missed the one before, then every other week back to creation.
    private static func weeklyLog(_ task: RoutineTask, today: String, streaks: [Int: Int]) -> [String] {
        let todayWeekday = RoutineDate.weekday(today)
        var log: [String] = []
        for (day, count) in streaks {
            var date = RoutineDate.adding(-((todayWeekday - day + 7) % 7), to: today)
            if date == today {
                date = RoutineDate.adding(-7, to: date)
            }
            var index = 0
            while date >= task.created, task.isScheduled(on: date) || task.isOffWeek(on: date) {
                if task.isScheduled(on: date) {
                    if index < count || (index > count && index % 2 == 0) {
                        log.append(date)
                    }
                    index += 1
                }
                date = RoutineDate.adding(-7, to: date)
            }
        }
        return log.sorted()
    }

    /// --uitest-demo: snapshots the demo routine (today, today with one
    /// more task marked done, a weekend day) to /tmp/obf_demo_*.png, quits.
    static func snapshot(appState: AppState) {
        func snap(_ name: String) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/obf_demo_\(name).png"))
        }
        func after(_ t: Double, _ block: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
        }
        after(1.0) {
            snap("1_today")
            if let biweekly = appState.routine.tasks.first(where: { $0.text.hasPrefix("Задача «А»") }) {
                appState.routineEditor = RoutineEditorRequest(day: appState.routineToday, itemID: biweekly.id)
            }
        }
        after(2.0) {
            if let sheet = NSApp.windows.first(where: { $0.isVisible })?.attachedSheet,
               let view = sheet.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "/tmp/obf_demo_1b_edit_biweekly.png"))
            }
            appState.routineEditor = nil
        }
        after(3.0) {
            if let rise = appState.routine.tasks.first(where: { $0.text == "Подъём в 8 утра" }) {
                appState.toggleRoutineDone(rise.id)
            }
            after(0.8) {
                snap("2_rise_done")
                appState.selectRoutineDay(1)
                after(0.8) {
                    snap("3_tuesday")
                    appState.selectRoutineDay(appState.routineToday)
                    after(0.8) { dragTest(snap: snap, appState: appState) }
                }
            }
        }
    }

    /// Drags the first card of today (the lecture) down past the next two
    /// with real mouse events, snapshotting mid-drag and after the drop.
    /// Mouse-down may start a tracking loop that only services event-
    /// tracking run-loop modes, so the moves are queued up front and the
    /// follow-up steps run on timers scheduled in all common modes.
    private static func dragTest(snap: @escaping (String) -> Void, appState: AppState) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { exit(1) }
        setvbuf(stdout, nil, _IOLBF, 0)
        print("DEMO-WINDOW active=\(NSApp.isActive) key=\(window.isKeyWindow)")
        let before = appState.routineItemsForDisplay(day: appState.routineToday).map(\.text)
        // Sidebar text column, first card (window coordinates, origin at
        // the bottom left).
        let x = OBFTheme.windowWidth - OBFTheme.contentPadding - OBFTheme.sidebarWidth + 90
        let startY = OBFTheme.windowHeight - 200
        func post(_ type: NSEvent.EventType, _ y: CGFloat) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
            else { return }
            NSApp.postEvent(event, atStart: false)
        }
        func later(_ t: Double, _ block: @escaping () -> Void) {
            let timer = Timer(timeInterval: t, repeats: false) { _ in block() }
            RunLoop.main.add(timer, forMode: .common)
            RunLoop.main.add(timer, forMode: .eventTracking)
        }
        post(.leftMouseDown, startY)
        for step in 1...20 {
            post(.leftMouseDragged, startY - 190 * CGFloat(step) / 20)
        }
        later(0.6) {
            snap("4_dragging")
            print("DEMO-DRAG mid order=\(appState.routineItemsForDisplay(day: appState.routineToday).map(\.text).first ?? "")")
            post(.leftMouseUp, startY - 190)
            later(0.8) {
                snap("5_dropped")
                let after = appState.routineItemsForDisplay(day: appState.routineToday).map(\.text)
                print("DEMO-DRAG before=\(before)")
                print("DEMO-DRAG after=\(after)")
                print("DEMO-SNAP done")
                exit(0)
            }
        }
    }
}
