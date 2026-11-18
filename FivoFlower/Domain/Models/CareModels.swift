import Foundation

// MARK: - Action types

struct CareActionType: Identifiable, Hashable {
    var id: UUID
    var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int
}

enum BuiltInCareAction {
    static let all: [(key: String, name: String)] = [
        ("repot", "换盆"),
        ("prune", "修剪"),
        ("water", "浇水"),
        ("fertilize", "施肥"),
        ("pest", "杀虫"),
        ("fungus", "杀菌")
    ]

    /// 曾经内置但已移除的类型，升级时一并清理历史数据。
    static let deprecatedKeys: Set<String> = ["other"]
}

// MARK: - Care log

struct CareLog: Identifiable, Hashable {
    var id: UUID
    var plantID: UUID
    var actionTypeID: UUID?
    var actionNameSnapshot: String
    var occurredAt: Date
    var note: String?
    var dosage: String?
    var unit: String?
    var batchID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var dosageText: String? {
        switch (dosage, unit) {
        case let (value?, unit?) where !unit.isEmpty:
            return "\(value) \(unit)"
        case let (value?, _):
            return value
        default:
            return nil
        }
    }
}

// MARK: - Reminders

enum ReminderStatus: String, Codable, CaseIterable {
    case pending
    case completed
    case skipped

    var title: String {
        switch self {
        case .pending: return "待处理"
        case .completed: return "已完成"
        case .skipped: return "已跳过"
        }
    }
}

enum ReminderRecurrence: Equatable, Hashable {
    case everyNDays(Int)
    case everyNWeeks(Int)
    case everyNMonths(Int)
    case everyNYears(Int)

    var title: String {
        switch self {
        case .everyNDays(let value): return "每 \(max(1, value)) 天"
        case .everyNWeeks(let value): return "每 \(max(1, value)) 周"
        case .everyNMonths(let value): return "每 \(max(1, value)) 月"
        case .everyNYears(let value): return "每 \(max(1, value)) 年"
        }
    }

    var rawValue: String {
        switch self {
        case .everyNDays(let value): return "every:\(max(1, value))"
        case .everyNWeeks(let value): return "weeks:\(max(1, value))"
        case .everyNMonths(let value): return "months:\(max(1, value))"
        case .everyNYears(let value): return "years:\(max(1, value))"
        }
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let value = Int(parts[1]), value >= 1 else { return nil }
        switch parts[0] {
        case "every": self = .everyNDays(value)
        case "weeks": self = .everyNWeeks(value)
        case "months": self = .everyNMonths(value)
        case "years": self = .everyNYears(value)
        default: return nil
        }
    }

    /// 以实际完成时间计算下一次待办；月/年遇到不存在的同日时取目标月末。
    func nextDue(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .everyNDays(let value):
            return calendar.date(byAdding: .day, value: max(1, value), to: date)
        case .everyNWeeks(let value):
            return calendar.date(byAdding: .day, value: 7 * max(1, value), to: date)
        case .everyNMonths(let value):
            return addingMonths(max(1, value), to: date, calendar: calendar)
        case .everyNYears(let value):
            return addingMonths(12 * max(1, value), to: date, calendar: calendar)
        }
    }

    private func addingMonths(_ value: Int, to date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        guard let sourceMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let targetMonth = calendar.date(byAdding: .month, value: value, to: sourceMonth),
              let dayCount = calendar.range(of: .day, in: .month, for: targetMonth)?.count else {
            return nil
        }
        let targetComponents = calendar.dateComponents([.year, .month], from: targetMonth)
        components.year = targetComponents.year
        components.month = targetComponents.month
        components.day = min(components.day ?? 1, dayCount)
        return calendar.date(from: components)
    }
}

struct CareReminder: Identifiable, Hashable {
    var id: UUID
    var plantID: UUID
    var actionTypeID: UUID?
    var actionNameSnapshot: String?
    var title: String
    var dueAt: Date
    var recurrence: ReminderRecurrence
    var status: ReminderStatus
    var completedAt: Date?
    var notificationID: String?
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var notificationIdentifier: String { "care-reminder-\(id.uuidString)" }
}

struct ReminderBucket: Identifiable {
    var title: String
    var reminders: [CareReminder]

    var id: String { title }
}

enum ReminderGrouping {
    static func pendingBuckets(reminders: [CareReminder], now: Date, calendar: Calendar) -> [ReminderBucket] {
        let pending = reminders.filter { $0.status == .pending }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var overdue: [CareReminder] = []
        var todayItems: [CareReminder] = []
        var upcoming: [CareReminder] = []
        for reminder in pending {
            let dueDay = calendar.startOfDay(for: reminder.dueAt)
            if dueDay < today {
                overdue.append(reminder)
            } else if dueDay < tomorrow {
                todayItems.append(reminder)
            } else {
                upcoming.append(reminder)
            }
        }
        let sort: (CareReminder, CareReminder) -> Bool = { $0.dueAt < $1.dueAt }
        var buckets: [ReminderBucket] = []
        if !overdue.isEmpty {
            buckets.append(ReminderBucket(title: "逾期", reminders: overdue.sorted(by: sort)))
        }
        if !todayItems.isEmpty {
            buckets.append(ReminderBucket(title: "今天", reminders: todayItems.sorted(by: sort)))
        }
        if !upcoming.isEmpty {
            buckets.append(ReminderBucket(title: "即将到期", reminders: upcoming.sorted(by: sort)))
        }
        return buckets
    }

    static func history(reminders: [CareReminder]) -> [CareReminder] {
        reminders
            .filter { $0.status != .pending }
            .sorted { ($0.completedAt ?? $0.dueAt) > ($1.completedAt ?? $1.dueAt) }
    }
}

struct CareBatchResult {
    var logs: [CareLog]
    var batchID: UUID
}

struct CareRecordDraft {
    var plantIDs: [UUID]
    var actionTypeID: UUID?
    var occurredAt: Date
    var note: String
    var dosage: String
    var unit: String
    var photos: [ImagePayload]
}

struct ReminderDraft {
    var plantIDs: [UUID]
    var actionTypeID: UUID?
    var title: String
    var dueAt: Date
    var recurrence: ReminderRecurrence
}

// MARK: - Derived care status and calendar

struct PlantCareStatus: Identifiable, Hashable {
    var id: String
    var actionTypeID: UUID?
    var actionName: String
    var lastOperatedAt: Date?
    var nextDueAt: Date?
}

enum PlantCareStatusCalculator {
    static func statuses(
        actionTypes: [CareActionType],
        logs: [CareLog],
        reminders: [CareReminder]
    ) -> [PlantCareStatus] {
        var statuses = actionTypes
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { action in
                PlantCareStatus(
                    id: action.id.uuidString,
                    actionTypeID: action.id,
                    actionName: action.name,
                    lastOperatedAt: nil,
                    nextDueAt: nil
                )
            }

        func matches(_ actionTypeID: UUID?, _ name: String, _ status: PlantCareStatus) -> Bool {
            if let actionTypeID, let statusID = status.actionTypeID {
                return actionTypeID == statusID
            }
            return name == status.actionName
        }

        func appendExtra(actionTypeID: UUID?, name: String) {
            guard !name.isEmpty,
                  !statuses.contains(where: { matches(actionTypeID, name, $0) }) else { return }
            statuses.append(PlantCareStatus(
                id: actionTypeID?.uuidString ?? "name:\(name)",
                actionTypeID: actionTypeID,
                actionName: name,
                lastOperatedAt: nil,
                nextDueAt: nil
            ))
        }

        for log in logs {
            appendExtra(actionTypeID: log.actionTypeID, name: log.actionNameSnapshot)
        }
        for reminder in reminders where reminder.status == .pending {
            appendExtra(
                actionTypeID: reminder.actionTypeID,
                name: reminder.actionNameSnapshot ?? reminder.title
            )
        }

        return statuses.map { status in
            var derived = status
            derived.lastOperatedAt = logs
                .filter { matches($0.actionTypeID, $0.actionNameSnapshot, status) }
                .map(\.occurredAt)
                .max()
            derived.nextDueAt = reminders
                .filter {
                    $0.status == .pending
                        && matches($0.actionTypeID, $0.actionNameSnapshot ?? $0.title, status)
                }
                .map(\.dueAt)
                .min()
            return derived
        }
    }
}

struct CareCalendarDay: Identifiable, Hashable {
    var date: Date
    var dayNumber: Int
    var isInDisplayedMonth: Bool
    var pendingCount: Int

    var id: Date { date }
}

enum CareCalendarCalculator {
    static func days(
        forMonthContaining date: Date,
        reminders: [CareReminder],
        calendar: Calendar
    ) -> [CareCalendarDay] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? calendar.startOfDay(for: date)
        let firstWeekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -firstWeekdayOffset, to: monthStart) else {
            return []
        }
        let pending = reminders.filter { $0.status == .pending }
        let counts = pending.reduce(into: [Date: Int]()) { result, reminder in
            result[calendar.startOfDay(for: reminder.dueAt), default: 0] += 1
        }

        return (0..<42).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let startOfDay = calendar.startOfDay(for: day)
            return CareCalendarDay(
                date: startOfDay,
                dayNumber: calendar.component(.day, from: startOfDay),
                isInDisplayedMonth: calendar.isDate(startOfDay, equalTo: monthStart, toGranularity: .month),
                pendingCount: counts[startOfDay, default: 0]
            )
        }
    }

    static func pendingReminders(
        on date: Date,
        reminders: [CareReminder],
        calendar: Calendar
    ) -> [CareReminder] {
        reminders
            .filter { $0.status == .pending && calendar.isDate($0.dueAt, inSameDayAs: date) }
            .sorted { $0.dueAt < $1.dueAt }
    }
}
