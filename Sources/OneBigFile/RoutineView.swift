import AppKit
import SwiftUI

/// Sidebar "Рутина" tab: a weekday switcher (the neighbouring days small
/// on a row above, the shown day large under them), a "+" that adds an
/// item to that day, and the day's items. Items of today carry a
/// "Выполнено" footer; done items dim. Click selects a card (Delete
/// removes it, Cmd+Z restores it), double click edits it.
struct RoutineView: View {
    @EnvironmentObject private var appState: AppState

    static let dayAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            RoutineDayHeader()
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle()
                .fill(OBFTheme.border)
                .frame(height: 1)
                .padding(.horizontal, 10)

            ZStack {
                RoutineDayList(day: appState.routineDay)
                    .id(appState.routineDay)
                    .transition(dayTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(Self.dayAnimation, value: appState.routineDay)
        }
    }

    /// The new day slides in from the side the user moved towards; the old
    /// one slides out the other way.
    private var dayTransition: AnyTransition {
        let forward = appState.routineDayForward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }
}

private struct RoutineDayHeader: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let day = appState.routineDay
        VStack(spacing: 6) {
            HStack {
                NeighborDayButton(day: (day + 6) % 7, forward: false)
                Spacer(minLength: 8)
                NeighborDayButton(day: (day + 1) % 7, forward: true)
            }
            .animation(RoutineView.dayAnimation, value: day)

            VStack(spacing: 1) {
                Text(Weekday.names[day])
                    .font(OBFTheme.uiBold(22))
                    .foregroundColor(OBFTheme.strong)
                    .lineLimit(1)
                // Date of that day in the current week.
                Text(RoutineDate.short(appState.routineDate(for: day)))
                    .font(OBFTheme.ui(12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(RoutineView.dayAnimation, value: day)
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                caption(day)
                Spacer(minLength: 4)
                AddRoutineButton {
                    appState.routineEditor = RoutineEditorRequest(day: day, itemID: nil)
                }
            }
        }
    }

    @ViewBuilder private func caption(_ day: Int) -> some View {
        // Tasks in their off week do not count.
        let items = appState.routine.tasks(on: day).filter { appState.isRoutineItemActive($0, day: day) }
        HStack(spacing: 6) {
            if day == appState.routineToday {
                Circle()
                    .fill(OBFTheme.h1Text)
                    .frame(width: 6, height: 6)
                Text(items.isEmpty
                     ? "Сегодня"
                     : "Сегодня · \(items.filter(appState.isRoutineItemDone).count) из \(items.count)")
            } else {
                Text(Self.itemCount(items.count))
            }
        }
        .font(OBFTheme.ui(12))
        .foregroundColor(.secondary)
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.2), value: items)
    }

    /// "1 пункт", "3 пункта", "7 пунктов".
    static func itemCount(_ n: Int) -> String {
        if n == 0 { return "Пока пусто" }
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "пункт"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "пункта"
        } else {
            word = "пунктов"
        }
        return "\(n) \(word)"
    }
}

private struct NeighborDayButton: View {
    @EnvironmentObject private var appState: AppState
    let day: Int
    let forward: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            appState.selectRoutineDay(day, forward: forward)
        } label: {
            HStack(spacing: 4) {
                if !forward { chevron("chevron.left") }
                Text(Weekday.names[day])
                    .font(OBFTheme.ui(12))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if forward { chevron("chevron.right") }
            }
            .foregroundColor(hovering ? OBFTheme.text : .secondary)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .semibold))
    }
}

private struct AddRoutineButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hovering ? OBFTheme.bg : OBFTheme.text)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? OBFTheme.h1Text : OBFTheme.elevated))
                .overlay(Circle().stroke(hovering ? Color.clear : OBFTheme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .help("Добавить в рутину")
    }
}

/// Layout frames of the cards, in the list's coordinate space.
private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The cards of one day. Cards that are not done can be dragged: the
/// picked-up card lifts and follows the pointer while the others slide out
/// of its way; the order is saved on drop. Done cards stay below.
private struct RoutineDayList: View {
    @EnvironmentObject private var appState: AppState
    let day: Int

    static let spacing: CGFloat = 8
    private static let space = "routineList"
    private static let slide = Animation.spring(response: 0.3, dampingFraction: 0.8)

    @State private var frames: [UUID: CGRect] = [:]
    /// The card being dragged and the live order of the draggable cards.
    @State private var dragID: UUID?
    @State private var dragOrder: [UUID]?
    @State private var dragTranslation: CGFloat = 0
    /// Layout position of the dragged card and of the list top at pick-up.
    @State private var dragStartMinY: CGFloat = 0
    @State private var listTop: CGFloat = 0
    /// Mouse-up of a drag must not count as a click on the card.
    @State private var lastDragEnd = Date.distantPast

    var body: some View {
        let items = appState.routineItemsForDisplay(day: day)
        let isToday = day == appState.routineToday
        let on = items.filter { appState.isRoutineItemActive($0, day: day) }
        let active = on.filter { !isToday || !appState.isRoutineItemDone($0) }
        // Done today, then off-week tasks: both stay below and do not drag.
        let rest = items.filter { !active.contains($0) }
        let activeIDs = active.map(\.id)
        let shown = (dragOrder ?? activeIDs).compactMap { id in active.first { $0.id == id } } + rest

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    ForEach(shown) { item in
                        let dragging = item.id == dragID
                        RoutineCardView(
                            item: item,
                            day: day,
                            isToday: isToday,
                            done: isToday && appState.isRoutineItemDone(item),
                            offWeek: !appState.isRoutineItemActive(item, day: day),
                            selected: appState.selectedRoutineItemIDs.contains(item.id),
                            ignoresTap: { Date().timeIntervalSince(lastDragEnd) < 0.25 })
                            .scaleEffect(dragging ? 1.03 : 1)
                            .shadow(color: .black.opacity(dragging ? 0.45 : 0), radius: dragging ? 12 : 0, y: dragging ? 6 : 0)
                            .offset(y: dragging ? dragOffset(item.id) : 0)
                            // Measured outside the offset and scale: the
                            // card's layout slot, not where it is drawn.
                            .background(GeometryReader { geo in
                                Color.clear.preference(
                                    key: CardFramesKey.self,
                                    value: [item.id: geo.frame(in: .named(Self.space))])
                            })
                            .zIndex(dragging ? 1 : 0)
                            // The lifted card tracks the pointer without
                            // lag; everything else animates.
                            .transaction { if dragging { $0.animation = nil } }
                            .gesture(activeIDs.contains(item.id) && activeIDs.count > 1
                                     ? dragGesture(item.id, activeIDs: activeIDs) : nil)
                            .transition(.asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.94, anchor: .top))
                                    .combined(with: .offset(y: -8)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.9, anchor: .center))))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .coordinateSpace(name: Self.space)
                .onPreferenceChange(CardFramesKey.self) { frames = $0 }
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: items)
                .animation(Self.slide, value: shown.map(\.id))
                .animation(.easeInOut(duration: 0.15), value: appState.selectedRoutineItemIDs)
            }
            // Clicking the empty space below the cards drops the selection.
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { appState.selectedRoutineItemIDs = [] })

            if items.isEmpty {
                VStack(spacing: 6) {
                    Text("На этот день ничего нет")
                        .font(OBFTheme.ui(14))
                        .foregroundColor(.secondary)
                    Text("Нажмите «+», чтобы добавить")
                        .font(OBFTheme.ui(12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: items.isEmpty)
    }

    /// Keeps the dragged card under the pointer while its layout slot moves
    /// as the others make room.
    private func dragOffset(_ id: UUID) -> CGFloat {
        dragStartMinY + dragTranslation - (frames[id]?.minY ?? dragStartMinY)
    }

    private func dragGesture(_ id: UUID, activeIDs: [UUID]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragID == nil {
                    dragID = id
                    dragOrder = activeIDs
                    dragStartMinY = frames[id]?.minY ?? 0
                    listTop = activeIDs.compactMap { frames[$0]?.minY }.min() ?? 0
                }
                dragTranslation = value.translation.height
                let order = Self.targetOrder(
                    dragged: id,
                    center: dragStartMinY + dragTranslation + (frames[id]?.height ?? 0) / 2,
                    order: dragOrder ?? activeIDs,
                    heights: frames.mapValues(\.height),
                    top: listTop)
                if order != dragOrder {
                    withAnimation(Self.slide) { dragOrder = order }
                }
            }
            .onEnded { _ in
                if let order = dragOrder {
                    appState.reorderRoutineItems(day: day, activeOrder: order)
                }
                lastDragEnd = Date()
                // The card settles into its new slot.
                withAnimation(Self.slide) {
                    dragID = nil
                    dragOrder = nil
                    dragTranslation = 0
                }
            }
    }

    /// Where the dragged card belongs: stacking the other cards from `top`,
    /// it goes before the first card whose middle lies below its center.
    /// Uses heights only, so the answer does not depend on where the
    /// dragged card itself currently sits (no flip-flopping).
    static func targetOrder(dragged: UUID, center: CGFloat, order: [UUID],
                            heights: [UUID: CGFloat], top: CGFloat) -> [UUID] {
        var others = order.filter { $0 != dragged }
        var y = top
        var index = others.count
        for (i, id) in others.enumerated() {
            let height = heights[id] ?? 0
            if center < y + height / 2 {
                index = i
                break
            }
            y += height + spacing
        }
        others.insert(dragged, at: index)
        return others
    }
}

/// One routine task: the full (never truncated) text, for a task that
/// repeats on several days a small "Вт · Чт · Сб" line under it, and — on
/// today's list — a square check button on the right, split off by a
/// hairline and as tall as the card. Done tasks dim and sink below the
/// active ones.
private struct RoutineCardView: View {
    @EnvironmentObject private var appState: AppState
    let item: RoutineTask
    let day: Int
    let isToday: Bool
    let done: Bool
    /// Every-other-week task in its off week: dimmed, no check button, the
    /// next due date instead.
    var offWeek = false
    let selected: Bool
    var ignoresTap: () -> Bool = { false }

    private static let shape = RoundedRectangle(cornerRadius: 10)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                let streak = item.streak(today: appState.todayKey)
                if !streak.isEmpty {
                    StreakLine(streak: streak)
                }
                Text(item.text)
                    .font(OBFTheme.ui(14))
                    .foregroundColor(OBFTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = planCaption(streak) {
                    Text(caption)
                        .font(OBFTheme.ui(11))
                        .foregroundColor(.secondary)
                }
                if let time = item.time {
                    (Text(Image(systemName: "clock")) + Text(" " + time.label))
                        .font(OBFTheme.ui(11))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                if offWeek, let next = item.nextDueDate(after: appState.routineDate(for: day)) {
                    Text("Следующий раз: \(RoutineDate.short(next))")
                        .font(OBFTheme.ui(11))
                        .foregroundColor(OBFTheme.text.opacity(0.8))
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .opacity(done ? 0.4 : (offWeek ? 0.5 : 1))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !ignoresTap() else { return }
                    // Handled on every click (no double-click delay); the
                    // click count tells a double click apart.
                    let event = NSApp.currentEvent
                    appState.clickRoutineItem(item.id, day: day,
                                              clickCount: event?.clickCount ?? 1,
                                              shift: event?.modifierFlags.contains(.shift) ?? false)
                }

            if isToday && !offWeek {
                Rectangle()
                    .fill(selected ? OBFTheme.selection.opacity(0.6) : OBFTheme.border)
                    .frame(width: 1)
                RoutineCheckButton(done: done) {
                    appState.toggleRoutineDone(item.id)
                }
            }
        }
        // Children with maxHeight .infinity stretch to the text's height:
        // the check column always spans the whole card.
        .fixedSize(horizontal: false, vertical: true)
        .background(Self.shape.fill(selected ? OBFTheme.selection.opacity(0.22) : OBFTheme.elevated))
        .clipShape(Self.shape)
        .overlay(Self.shape.stroke(selected ? OBFTheme.selection : OBFTheme.border,
                                   lineWidth: selected ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.22), value: done)
    }

    /// Small line under the text: the days ("Вт · Чт", "Каждый день") and
    /// the repetition ("через неделю"). The weekly streak line already
    /// names the days, so then only the repetition remains.
    private func planCaption(_ streak: RoutineStreak) -> String? {
        let days = item.currentDays
        let interval = Weekday.interval(item.everyWeeks)
        var parts: [String] = []
        if days.count > 1, streak.isEmpty || days.count == 7 {
            parts.append(Weekday.summary(days))
        } else if days.count == 1, interval != nil, streak.isEmpty {
            parts.append(Weekday.shortNames[days.first!])
        }
        if let interval {
            parts.append(interval)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Streak above a card's text: a flame and "12 дней подряд" for an
/// every-day task, or "ВТ-3 · ЧТ-5 · СБ-1" per weekday (up to two lines);
/// days at zero are dimmer.
private struct StreakLine: View {
    let streak: RoutineStreak

    var body: some View {
        // One concatenated Text so a long weekly line wraps onto a second
        // line. Inside an entry the hyphen and the space before "·" are
        // non-breaking: lines only break between days ("ВТ-3 ·" | "ЧТ-5").
        var line = Text(Image(systemName: "flame.fill"))
            .font(.system(size: 10))
            .foregroundColor(OBFTheme.h1Text)
            + Text(" ")
        switch streak {
        case .daily(let count):
            line = line + Text(Self.daysInRow(count)).foregroundColor(OBFTheme.h1Text)
        case .weekly(let days):
            for (index, entry) in days.enumerated() {
                if index > 0 {
                    line = line + Text("\u{00A0}· ").foregroundColor(.secondary)
                }
                line = line + Text("\(Weekday.shortNames[entry.day].uppercased())\u{2011}\(entry.count)")
                    .foregroundColor(entry.count > 0 ? OBFTheme.h1Text : .secondary)
            }
        }
        return line
            .font(OBFTheme.ui(11))
            .monospacedDigit()
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "1 день подряд", "3 дня подряд", "12 дней подряд".
    static func daysInRow(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let word: String
        if mod10 == 1 && mod100 != 11 {
            word = "день"
        } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            word = "дня"
        } else {
            word = "дней"
        }
        return "\(n) \(word) подряд"
    }
}

/// A thin, open checkmark, drawn to scale with its frame.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Right-hand column of a today card that marks it done. Idle: a faint
/// checkmark that brightens on hover. Done: a green checkmark on a soft
/// green tint.
private struct RoutineCheckButton: View {
    let done: Bool
    let action: () -> Void
    @State private var hovering = false

    static let width: CGFloat = 44

    var body: some View {
        Button(action: action) {
            CheckmarkShape()
                .stroke(color, style: StrokeStyle(lineWidth: done ? 2 : 1.4,
                                                  lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 12)
                .frame(width: Self.width)
                .frame(maxHeight: .infinity)
                .background(done
                            ? OBFTheme.done.opacity(hovering ? 0.2 : 0.13)
                            : (hovering ? OBFTheme.hover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: done)
        .help(done ? "Снять отметку" : "Выполнено")
    }

    private var color: Color {
        if done { return OBFTheme.done }
        return hovering ? OBFTheme.text : OBFTheme.text.opacity(0.35)
    }
}

/// Modal for adding a routine item to a weekday or editing one.
struct RoutineEditorView: View {
    @EnvironmentObject private var appState: AppState
    let request: RoutineEditorRequest
    @State private var text = ""
    /// Weekdays the task repeats on: for a new task the day the modal was
    /// opened for, for an existing one its current days. All seven = "На
    /// каждый день".
    @State private var days: Set<Int> = []
    /// Repetition: every N weeks, starting `startOffset` weeks from now.
    @State private var everyWeeks = 1
    @State private var startOffset = 0
    /// Raw time fields, "HH:MM" as typed.
    @State private var timeStart = ""
    @State private var timeEnd = ""
    @FocusState private var focused: Bool

    static let width: CGFloat = 460

    private var isNew: Bool { request.itemID == nil }
    private var everyDay: Bool { days.count == 7 }
    private var time: Result<RoutineTime?, RoutineTimeError> {
        RoutineTime.from(start: timeStart, end: timeEnd)
    }

    private var canSave: Bool {
        guard case .success = time else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !days.isEmpty
    }

    /// Modal title: the single day, "Каждый день", or the short names of
    /// the chosen days.
    private var title: String {
        if days.count == 1, let day = days.first { return Weekday.names[day] }
        if days.isEmpty { return "Выберите дни" }
        return Weekday.summary(days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(OBFTheme.h1Text)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "Новый пункт рутины" : "Изменить пункт рутины")
                        .font(OBFTheme.ui(12))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(OBFTheme.uiBold(22))
                        .foregroundColor(days.isEmpty ? .secondary : OBFTheme.strong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: title)
                }

                TextField("Например: подъём в 8 утра", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(OBFTheme.ui(15))
                    .foregroundColor(OBFTheme.text)
                    .lineLimit(3...10)
                    .focused($focused)
                    .onSubmit(save)
                    .padding(12)
                    .background(OBFTheme.bg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(focused ? OBFTheme.selection : OBFTheme.border, lineWidth: 1))

                RoutineDayPicker(days: $days)

                RoutineTimePicker(start: $timeStart, end: $timeEnd, error: {
                    if case .failure(let error) = time { return error }
                    return nil
                }())

                RoutineRepeatPicker(everyWeeks: $everyWeeks, startOffset: $startOffset,
                                    dates: dueDatesPreview)

                HStack(spacing: 10) {
                    if let id = request.itemID {
                        Button("Удалить из всех дней") {
                            appState.deleteRoutineTaskEverywhere(id, day: request.day)
                            appState.routineEditor = nil
                        }
                        .buttonStyle(DestructiveButtonStyle())
                    }
                    Spacer()
                    Button("Отмена") { appState.routineEditor = nil }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(ModalButtonStyle(filled: false, accent: OBFTheme.h1Text))
                    Button(isNew ? "Добавить" : "Сохранить", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(ModalButtonStyle(filled: true, accent: OBFTheme.h1Text))
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.45)
                }
            }
            .padding(24)
        }
        .frame(width: Self.width)
        .background(OBFTheme.elevated)
        .presentationBackground(OBFTheme.elevated)
        .preferredColorScheme(OBFTheme.colorScheme)
        .onAppear {
            if let id = request.itemID, let task = appState.routineTask(id) {
                text = task.text
                days = task.currentDays
                everyWeeks = task.everyWeeks
                timeStart = task.time?.start ?? ""
                timeEnd = task.time?.end ?? ""
                // The nearest week the task is on, counted from this one.
                let thisWeek = RoutineDate.weekStart(appState.todayKey)
                startOffset = (0..<max(1, everyWeeks)).first {
                    task.isActiveWeek(RoutineDate.adding(7 * $0, to: thisWeek))
                } ?? 0
            } else {
                days = [request.day]
            }
            DispatchQueue.main.async { focused = true }
        }
    }

    /// The next due dates (from today on) for the chosen days and
    /// repetition, e.g. ["24.09", "8.10", "22.10", "5.11"].
    private var dueDatesPreview: [String] {
        guard everyWeeks > 1, !days.isEmpty else { return [] }
        let plan = appState.routinePlan(days: days, everyWeeks: everyWeeks, startOffset: startOffset)
        var result: [String] = []
        var date = appState.todayKey
        for _ in 0..<(7 * 60) where result.count < 4 {
            if days.contains(RoutineDate.weekday(date)) && plan.isActiveWeek(date) {
                result.append(RoutineDate.short(date))
            }
            date = RoutineDate.adding(1, to: date)
        }
        return result
    }

    private func save() {
        guard canSave else { return }
        if let id = request.itemID {
            appState.updateRoutineItem(id, text: text, days: days,
                                       everyWeeks: everyWeeks, startOffset: startOffset,
                                       time: try? time.get())
        } else {
            appState.addRoutineItem(text, days: days.sorted(),
                                    everyWeeks: everyWeeks, startOffset: startOffset,
                                    time: try? time.get())
        }
        appState.routineEditor = nil
    }
}

/// Time of the edit modal: 🕒 с [HH:MM] до [HH:MM]. Either field may stay
/// empty; digits are formatted as they are typed ("1555" -> "15:55"). A
/// wrong field (2424, 12:60, an end not after the start) turns red.
struct RoutineTimePicker: View {
    @Binding var start: String
    @Binding var end: String
    let error: RoutineTimeError?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("с")
            TimeField(text: $start, wrong: error == .start)
            Text("до")
            TimeField(text: $end, wrong: error == .end || error == .order)
            if !start.isEmpty || !end.isEmpty {
                Button {
                    start = ""
                    end = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Убрать время")
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            if error == .order {
                Text("конец раньше начала")
                    .font(OBFTheme.ui(12))
                    .foregroundColor(TimeField.red)
                    .transition(.opacity)
            }
        }
        .font(OBFTheme.ui(14))
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.15), value: error)
        .animation(.easeInOut(duration: 0.15), value: start.isEmpty && end.isEmpty)
    }
}

/// "HH:MM" input: keeps digits only, inserts the colon itself. It shows
/// red while `wrong` — except for a half-typed time while still focused.
private struct TimeField: View {
    static let red = Color(red: 0.93, green: 0.42, blue: 0.40)

    @Binding var text: String
    let wrong: Bool
    @FocusState private var focused: Bool

    private var showsError: Bool {
        guard wrong else { return false }
        // Typing "15:5" is not an error yet; a complete wrong time is.
        return !focused || text.filter(\.isNumber).count == 4
    }

    var body: some View {
        TextField("--:--", text: $text)
            .textFieldStyle(.plain)
            .font(OBFTheme.ui(14))
            .foregroundColor(showsError ? Self.red : OBFTheme.text)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 54)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(showsError ? Self.red.opacity(0.12) : OBFTheme.bg))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(showsError ? Self.red : (focused ? OBFTheme.selection : OBFTheme.border), lineWidth: 1))
            .focused($focused)
            .onChange(of: text) {
                let formatted = RoutineTime.format(text)
                if formatted != text { text = formatted }
            }
            .animation(.easeInOut(duration: 0.15), value: showsError)
    }
}

/// Repetition of the edit modal: "Каждую неделю" / "Через неделю" / "Раз
/// в [N] нед."; for anything but weekly also the first week — "С этой
/// недели" / "Со следующей" / "Через [N] нед." — and the dates it gives.
struct RoutineRepeatPicker: View {
    @Binding var everyWeeks: Int
    @Binding var startOffset: Int
    let dates: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Повтор")
                .font(OBFTheme.ui(12))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                OptionPill(title: "Каждую неделю", on: everyWeeks == 1) { everyWeeks = 1 }
                OptionPill(title: "Через неделю", on: everyWeeks == 2) { everyWeeks = 2 }
                NumberPill(prefix: "Раз в", suffix: "нед.", value: $everyWeeks,
                           on: everyWeeks >= 3, range: 1...52)
            }

            if everyWeeks > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Начало")
                        .font(OBFTheme.ui(12))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    HStack(spacing: 6) {
                        OptionPill(title: "С этой недели", on: startOffset == 0) { startOffset = 0 }
                        OptionPill(title: "Со следующей", on: startOffset == 1) { startOffset = 1 }
                        NumberPill(prefix: "Через", suffix: "нед.", value: $startOffset,
                                   on: startOffset >= 2, range: 0...52)
                    }
                    if !dates.isEmpty {
                        (Text("Даты: ").foregroundColor(.secondary)
                         + Text(dates.joined(separator: " · ") + " · …").foregroundColor(OBFTheme.h1Text))
                            .font(OBFTheme.ui(13))
                            .monospacedDigit()
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: everyWeeks > 1)
        .animation(.easeInOut(duration: 0.15), value: dates)
    }
}

/// A choice pill of the repeat picker; accent-tinted when chosen.
private struct OptionPill: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OBFTheme.ui(13))
                .foregroundColor(on || hovering ? OBFTheme.text : .secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(PillBackground(on: on, hovering: hovering))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: on)
    }
}

/// A pill with a number field ("Раз в [3] нед."); typing a number picks it.
private struct NumberPill: View {
    let prefix: String
    let suffix: String
    @Binding var value: Int
    let on: Bool
    let range: ClosedRange<Int>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(prefix)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .frame(width: 24)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(OBFTheme.bg))
                .focused($focused)
                .onChange(of: text) {
                    let digits = text.filter(\.isNumber)
                    if digits != text { text = digits; return }
                    if let number = Int(digits) {
                        value = min(range.upperBound, max(range.lowerBound, number))
                    }
                }
            Text(suffix)
        }
        .font(OBFTheme.ui(13))
        .foregroundColor(on || focused ? OBFTheme.text : .secondary)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(PillBackground(on: on, hovering: false))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { if on { text = "\(value)" } }
        // Another pill chosen: the field lets go of its number.
        .onChange(of: on) { if !on && !focused { text = "" } }
        .animation(.easeInOut(duration: 0.15), value: on)
    }
}

private struct PillBackground: View {
    let on: Bool
    let hovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(on ? OBFTheme.h1Text.opacity(0.14) : (hovering ? OBFTheme.hover : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(on ? OBFTheme.h1Text.opacity(0.6) : OBFTheme.border, lineWidth: 1))
    }
}

/// Day choice of the add modal: "На каждый день" on top, then the seven
/// weekdays as a plain list split by hairlines. Every day lights all days
/// up; picking a single day afterwards turns it and "На каждый день" off.
struct RoutineDayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PickerRow(title: "На каждый день", on: days.count == 7, emphasized: true) {
                days = RoutineDayPicker.toggledEveryDay(days)
            }

            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { day in
                    if day > 0 {
                        Rectangle()
                            .fill(OBFTheme.border)
                            .frame(height: 1)
                    }
                    PickerRow(title: Weekday.names[day], on: days.contains(day), emphasized: false) {
                        days = RoutineDayPicker.toggled(days, day)
                    }
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: days)
    }

    /// "На каждый день": all seven on; pressed again it clears them all.
    static func toggledEveryDay(_ days: Set<Int>) -> Set<Int> {
        days.count == 7 ? [] : Set(0..<7)
    }

    static func toggled(_ days: Set<Int>, _ day: Int) -> Set<Int> {
        var days = days
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        return days
    }
}

private struct PickerRow: View {
    let title: String
    let on: Bool
    let emphasized: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(on ? OBFTheme.h1Text : Color.clear)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(on ? OBFTheme.h1Text : OBFTheme.text.opacity(hovering ? 0.8 : 0.4), lineWidth: 1)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(OBFTheme.bg)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 15, height: 15)
                Text(title)
                    .font(emphasized
                          ? OBFTheme.uiBold(15)
                          : OBFTheme.ui(14))
                    .foregroundColor(on ? OBFTheme.text : (hovering ? OBFTheme.text.opacity(0.8) : .secondary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: emphasized ? 36 : 30)
            .background(emphasized
                        ? RoundedRectangle(cornerRadius: 7)
                            .fill(on ? OBFTheme.h1Text.opacity(0.12) : (hovering ? OBFTheme.hover : Color.clear))
                        : nil)
            .overlay(emphasized
                     ? RoundedRectangle(cornerRadius: 7)
                        .stroke(on ? OBFTheme.h1Text.opacity(0.5) : OBFTheme.border, lineWidth: 1)
                     : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }
}

/// Quiet red text button of the edit modal ("Удалить из всех дней"); a
/// soft red fill shows on hover.
private struct DestructiveButtonStyle: ButtonStyle {
    static let red = Color(red: 0.93, green: 0.42, blue: 0.40)

    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(OBFTheme.ui(14))
                .foregroundColor(DestructiveButtonStyle.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(DestructiveButtonStyle.red.opacity(hovering ? 0.14 : 0)))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeInOut(duration: 0.15), value: hovering)
        }
    }
}

/// Test access to the drag placement logic of the private day list.
enum RoutineDayListTesting {
    static func targetOrder(dragged: UUID, center: CGFloat, order: [UUID],
                            heights: [UUID: CGFloat], top: CGFloat) -> [UUID] {
        RoutineDayList.targetOrder(dragged: dragged, center: center, order: order,
                                   heights: heights, top: top)
    }
}
