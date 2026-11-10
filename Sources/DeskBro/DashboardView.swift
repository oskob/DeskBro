import SwiftUI

// MARK: - Theme

enum Theme {
    static let bgTop = Color(red: 0.067, green: 0.086, blue: 0.098)
    static let bgBottom = Color(red: 0.090, green: 0.110, blue: 0.122)
    static let card = Color(red: 0.110, green: 0.133, blue: 0.145)
    static let cardBorder = Color.white.opacity(0.06)
    static let divider = Color.white.opacity(0.07)

    static let accent = Color(red: 0.84, green: 0.93, blue: 0.67)       // pale lime
    static let accentInk = Color(red: 0.08, green: 0.11, blue: 0.08)    // text on accent
    static let text = Color(red: 0.93, green: 0.95, blue: 0.92)
    static let secondary = Color.white.opacity(0.48)
    static let tertiary = Color.white.opacity(0.30)
    static let danger = Color(red: 1.0, green: 0.52, blue: 0.48)
}

// MARK: - Root

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    let onDismiss: () -> Void
    /// Pins the clock (used to render the README demo); nil means the real time.
    var fixedNow: Date? = nil

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = fixedNow ?? context.date
            ZStack {
                LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    TopBar(now: now, onDismiss: onDismiss)

                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.userPreferred)))
                            .foregroundStyle(Theme.text)
                        Text(now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.tertiary)
                    }
                    .font(.system(size: 62, weight: .regular, design: .serif))
                    .padding(.top, 44)
                    .padding(.bottom, 36)

                    HStack(alignment: .top, spacing: 28) {
                        EventsCard(model: model, now: now)
                        RemindersCard(model: model, now: now)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 54)
                .padding(.top, 52)
                .padding(.bottom, 54)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let now: Date
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 14, weight: .semibold))
                Text("DESKBRO")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(3.5)
            }
            .foregroundStyle(Theme.accent)

            Spacer()

            DismissButton(action: onDismiss)
        }
    }
}

private struct DismissButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("Dismiss")
                    .font(.system(size: 18, weight: .semibold))
                Text("esc")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.accentInk.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .foregroundStyle(Theme.accentInk)
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .padding(.vertical, 13)
            .background(Theme.accent.opacity(hovering ? 1 : 0.92), in: Capsule())
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}

// MARK: - Card

private struct Card<Accessory: View, Content: View>: View {
    let symbol: String
    let count: Int?
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                Text(title)
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                accessory
                if let count {
                    Text("\(count)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.bottom, 26)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 31)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1)
    }
}

// MARK: - Events

private struct EventsCard: View {
    @ObservedObject var model: DashboardModel
    let now: Date

    var body: some View {
        Card(
            symbol: "calendar",
            count: model.calendarAccess == .granted ? model.events.filter { $0.isAllDay || $0.end > now }.count : nil,
            title: "Today’s agenda",
            accessory: { EmptyView() }
        ) {
            switch model.calendarAccess {
            case .denied:
                AccessDeniedView(what: "Calendar", settingsAnchor: "Privacy_Calendars")
            case .unknown:
                ProgressView().controlSize(.small).padding(.top, 20)
            case .granted:
                VStack(spacing: 0) {
                    Group {
                        if model.events.isEmpty {
                            EmptyStateView(symbol: "sun.horizon", title: "No events today")
                        } else {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    ForEach(model.events) { event in
                                        EventRow(event: event, now: now)
                                        RowDivider()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    WeekStrip(events: model.weekEvents, now: now)
                        .padding(.top, 20)
                }
            }
        }
    }
}

// MARK: - Week strip

private extension Locale {
    /// The user's preferred language (the app itself only ships English).
    static var userPreferred: Locale { Locale(identifier: Locale.preferredLanguages.first ?? "en") }
}

private struct WeekStrip: View {
    let events: [EventItem]
    let now: Date

    private var days: [Date] {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    private func events(on day: Date) -> [EventItem] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.start < end && $0.end > start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RowDivider()
                .padding(.bottom, 4)
            HStack {
                Text("This week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Text("W\(Calendar.current.component(.weekOfYear, from: now))")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    DayColumn(day: day, events: events(on: day), now: now)
                }
            }
        }
    }
}

private struct DayColumn: View {
    let day: Date
    let events: [EventItem]
    let now: Date

    private let maxVisible = 3
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: now) }
    private var isPast: Bool { day < Calendar.current.startOfDay(for: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.userPreferred)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isToday ? Theme.accent : Theme.tertiary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Theme.accent : Theme.text)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(events.prefix(maxVisible)) { event in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(event.color)
                            .frame(width: 3, height: 11)
                        Text(event.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                if events.count > maxVisible {
                    Text("+\(events.count - maxVisible) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? Theme.accent.opacity(0.07) : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isToday ? Theme.accent.opacity(0.35) : .clear, lineWidth: 1)
        )
        .opacity(isPast ? 0.45 : 1)
    }
}

private struct EventRow: View {
    let event: EventItem
    let now: Date

    private var isPast: Bool { !event.isAllDay && now >= event.end }
    private var isNow: Bool { !event.isAllDay && now >= event.start && now < event.end }
    private var minutesUntil: Int? {
        guard !event.isAllDay, now < event.start else { return nil }
        let m = Int(event.start.timeIntervalSince(now) / 60)
        return m <= 60 ? max(m, 1) : nil
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let f: (Date) -> String = { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
        return "\(f(event.start)) – \(f(event.end))"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Circle()
                .fill(event.color)
                .frame(width: 10, height: 10)
                .frame(width: 26) // align with reminder checkboxes

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(timeText).monospacedDigit()
                    if let location = event.location {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                    Text("·")
                    Text(event.calendarName)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 12)

            if isNow {
                Tag(text: "Now", filled: true)
            } else if let minutesUntil {
                Tag(text: "in \(minutesUntil) min", filled: false)
            }
        }
        .padding(.vertical, 18)
        .opacity(isPast ? 0.38 : 1)
    }
}

private struct Tag: View {
    let text: String
    let filled: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled ? Theme.accentInk : Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
    }
}

// MARK: - Reminders

private struct RemindersCard: View {
    @ObservedObject var model: DashboardModel
    let now: Date
    @State private var dragging: String?

    var body: some View {
        Card(
            symbol: "checklist",
            count: model.remindersAccess == .granted ? model.reminders.count : nil,
            title: "Reminders",
            accessory: { EmptyView() }
        ) {
            switch model.remindersAccess {
            case .denied:
                AccessDeniedView(what: "Reminders", settingsAnchor: "Privacy_Reminders")
            case .unknown:
                ProgressView().controlSize(.small).padding(.top, 20)
            case .granted:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(model.reminders) { item in
                            VStack(spacing: 0) {
                                ReminderRow(item: item, now: now) { model.complete(item) }
                                RowDivider()
                            }
                            .opacity(dragging == item.id ? 0.25 : 1)
                            .onDrag {
                                dragging = item.id
                                return NSItemProvider(object: item.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                targetId: item.id, model: model, dragging: $dragging))
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                        AddReminderRow(model: model)
                    }
                    // Catch drops between/below rows so the drag state always resets.
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(targetId: nil, model: model, dragging: $dragging))
                }
            }
        }
    }
}

private struct ReorderDropDelegate: DropDelegate {
    let targetId: String?
    let model: DashboardModel
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, let targetId else { return }
        model.moveReminder(dragging, to: targetId)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Always-visible "Add reminder" row under the last reminder.
private struct AddReminderRow: View {
    @ObservedObject var model: DashboardModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.accent.opacity(focused || hovering ? 0.8 : 0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: focused ? [] : [3, 3]))
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(focused || hovering ? 1 : 0.6))
            }
            .frame(width: 26, height: 26)

            TextField("", text: $text, prompt: Text("Add reminder").foregroundStyle(
                hovering && !focused ? Theme.accent.opacity(0.8) : Theme.tertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit(submit)

            if !text.isEmpty {
                Text("return ↵")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onHover { hovering = $0 }
    }

    private func submit() {
        if model.addReminder(title: text) { text = "" }
        focused = true // keep adding
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let now: Date
    let onComplete: () -> Void

    @State private var checked = false
    @State private var hovering = false
    @State private var rowHovering = false

    private var isOverdue: Bool {
        guard let due = item.due else { return false }
        return item.dueHasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    private var dueText: String? {
        guard let due = item.due else { return nil }
        let cal = Calendar.current
        let time = item.dueHasTime
            ? " " + due.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            : ""
        if cal.isDateInToday(due) { return "Today" + time }
        if cal.isDateInTomorrow(due) { return "Tomorrow" + time }
        if cal.isDateInYesterday(due) { return "Yesterday" + time }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + time
    }

    /// EventKit priority: 1–4 high, 5 medium, 6–9 low, 0 none.
    private var priorityMark: String? {
        switch item.priority {
        case 1...4: return "!!!"
        case 5: return "!!"
        case 6...9: return "!"
        default: return nil
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { checked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.3)) { onComplete() }
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(checked || hovering ? Theme.accent : Color.white.opacity(0.45), lineWidth: 1.5)
                    Circle()
                        .fill(Theme.accent)
                        .opacity(checked ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(checked ? Theme.accentInk : Theme.accent)
                        .opacity(checked ? 1 : (hovering ? 0.8 : 0))
                }
                .frame(width: 26, height: 26)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 7 }

            VStack(alignment: .leading, spacing: 6) {
                (priorityMark.map { Text($0 + " ").foregroundColor(Theme.accent) } ?? Text(""))
                + Text(item.title).foregroundColor(Theme.text)

                HStack(spacing: 6) {
                    if let dueText {
                        Text(dueText)
                            .foregroundStyle(isOverdue ? Theme.danger : Theme.secondary)
                        Text("·")
                    }
                    Text(item.listName)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 21, weight: .medium))
            .strikethrough(checked, color: Theme.secondary)
            .lineLimit(3)

            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .opacity(rowHovering && !checked ? 1 : 0)
                .help("Drag to reorder")
        }
        .padding(.vertical, 18)
        .contentShape(Rectangle())
        .onHover { rowHovering = $0 }
        .opacity(checked ? 0.45 : 1)
    }
}

// MARK: - Shared bits

private struct EmptyStateView: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }
}

private struct AccessDeniedView: View {
    let what: String
    let settingsAnchor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "lock")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("No access to \(what)")
                .font(.system(size: 23))
                .foregroundStyle(Theme.text)
            Text("Allow DeskBro in System Settings → Privacy & Security → \(what).")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open System Settings")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }
}
