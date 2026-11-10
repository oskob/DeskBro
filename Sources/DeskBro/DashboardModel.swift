import EventKit
import SwiftUI

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarName: String
    let color: Color
}

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let dueHasTime: Bool
    let listName: String
    let color: Color
    let priority: Int
}

enum AccessState {
    case unknown, granted, denied
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var events: [EventItem] = []       // today
    @Published var weekEvents: [EventItem] = []   // the whole current week
    @Published var reminders: [ReminderItem] = []
    @Published var calendarAccess: AccessState = .unknown
    @Published var remindersAccess: AccessState = .unknown

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    private var isReloading = false

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
    }

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        calendarAccess = granted ? .granted : .denied
        let remGranted = (try? await store.requestFullAccessToReminders()) ?? false
        remindersAccess = remGranted ? .granted : .denied
    }

    func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }

        // A long-lived EKEventStore caches aggressively; drop the cache and pull fresh data.
        store.refreshSourcesIfNecessary()
        store.reset()

        if calendarAccess == .granted { loadEvents() }
        if remindersAccess == .granted { await loadReminders() }
    }

    private func loadEvents() {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let week = cal.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: todayStart, end: todayEnd)
        let predicate = store.predicateForEvents(withStart: week.start, end: week.end, calendars: nil)

        let all = store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map { e in
                EventItem(
                    id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "Untitled",
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    location: (e.location?.isEmpty == false) ? e.location : nil,
                    calendarName: e.calendar.title,
                    color: Color(nsColor: e.calendar.color ?? .systemBlue)
                )
            }

        weekEvents = all
        events = all.filter { $0.start < todayEnd && $0.end > todayStart }
    }

    private func loadReminders() async {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let fetched: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }

        let cal = Calendar.current
        let items = fetched.map { r -> ReminderItem in
            let comps = r.dueDateComponents
            return ReminderItem(
                id: r.calendarItemIdentifier,
                title: r.title ?? "Untitled",
                due: comps.flatMap { cal.date(from: $0) },
                dueHasTime: comps?.hour != nil,
                listName: r.calendar.title,
                color: Color(nsColor: r.calendar.color ?? .systemOrange),
                priority: r.priority
            )
        }

        // Default: dated reminders first (soonest / most overdue on top), then undated by list.
        let defaultSorted = items.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil):
                if a.listName != b.listName { return a.listName < b.listName }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }

        // Apply the user's manual order (set by dragging); anything new goes to the bottom.
        let order = savedOrder
        guard !order.isEmpty else {
            reminders = defaultSorted
            return
        }
        let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let known = defaultSorted.filter { index[$0.id] != nil }.sorted { index[$0.id]! < index[$1.id]! }
        let new = defaultSorted.filter { index[$0.id] == nil }
        reminders = known + new
    }

    // MARK: - Manual order

    // EventKit doesn't expose the Reminders app's manual order, so DeskBro keeps its own.
    private let orderKey = "reminderOrder"

    private var savedOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: orderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: orderKey) }
    }

    /// Moves `id` to the position currently held by `targetId` (live, while dragging).
    func moveReminder(_ id: String, to targetId: String) {
        guard id != targetId,
              let from = reminders.firstIndex(where: { $0.id == id }),
              let to = reminders.firstIndex(where: { $0.id == targetId }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            reminders.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        savedOrder = reminders.map(\.id)
    }

    func complete(_ item: ReminderItem) {
        // Re-fetch by id: cached EKReminder objects are invalidated on every reload.
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            NSSound.beep()
            return
        }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                reminders.removeAll { $0.id == item.id }
            }
        } catch {
            NSSound.beep()
        }
    }

    /// Adds a reminder with the given title to the default Reminders list.
    @discardableResult
    func addReminder(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, remindersAccess == .granted,
              let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        do {
            try store.save(reminder, commit: true)
        } catch {
            NSSound.beep()
            return false
        }
        Task { await reload() }
        return true
    }
}
