import XCTest
@testable import FivoFlower

final class CareAndJournalEnhancementTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func action(id: UUID = UUID(), name: String = "浇水") -> CareActionType {
        CareActionType(id: id, key: "water", name: name, isBuiltIn: true, isEnabled: true, sortOrder: 0)
    }

    private func log(actionID: UUID?, name: String, occurredAt: Date) -> CareLog {
        CareLog(
            id: UUID(), plantID: UUID(), actionTypeID: actionID, actionNameSnapshot: name,
            occurredAt: occurredAt, note: nil, dosage: nil, unit: nil, batchID: nil,
            createdAt: occurredAt, updatedAt: occurredAt
        )
    }

    private func reminder(
        actionID: UUID? = nil,
        name: String = "浇水",
        dueAt: Date,
        recurrence: ReminderRecurrence = .everyNDays(1),
        status: ReminderStatus = .pending
    ) -> CareReminder {
        CareReminder(
            id: UUID(), plantID: UUID(), actionTypeID: actionID, actionNameSnapshot: name,
            title: name, dueAt: dueAt, recurrence: recurrence, status: status,
            completedAt: status == .pending ? nil : dueAt, notificationID: nil, groupID: nil,
            createdAt: dueAt, updatedAt: dueAt
        )
    }

    func testCareStatusUsesLatestLogAndEarliestPendingRecurringReminder() {
        let water = action()
        let logs = [
            log(actionID: water.id, name: water.name, occurredAt: date("2025-06-01 08:00")),
            log(actionID: water.id, name: water.name, occurredAt: date("2025-06-10 09:00"))
        ]
        let reminders = [
            reminder(actionID: water.id, dueAt: date("2025-06-11 08:00"), status: .completed),
            reminder(actionID: water.id, dueAt: date("2025-06-15 08:00"), recurrence: .everyNDays(3)),
            reminder(actionID: water.id, dueAt: date("2025-06-13 08:00"), recurrence: .everyNDays(3)),
            reminder(actionID: water.id, dueAt: date("2025-06-12 08:00"), recurrence: .everyNDays(3), status: .completed)
        ]

        let status = PlantCareStatusCalculator.statuses(
            actionTypes: [water], logs: logs, reminders: reminders
        ).first

        XCTAssertEqual(status?.lastOperatedAt, date("2025-06-10 09:00"))
        XCTAssertEqual(status?.nextDueAt, date("2025-06-13 08:00"))
    }

    func testCareStatusRetainsDeletedActionByNameSnapshot() {
        let statuses = PlantCareStatusCalculator.statuses(
            actionTypes: [],
            logs: [log(actionID: nil, name: "喷雾", occurredAt: date("2025-06-10 09:00"))],
            reminders: [reminder(name: "喷雾", dueAt: date("2025-06-15 09:00"), recurrence: .everyNWeeks(1))]
        )

        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.first?.actionName, "喷雾")
        XCTAssertEqual(statuses.first?.lastOperatedAt, date("2025-06-10 09:00"))
        XCTAssertEqual(statuses.first?.nextDueAt, date("2025-06-15 09:00"))
    }

    func testCalendarReturnsOnlyPendingRemindersOnSelectedDay() {
        let selected = date("2025-06-15 12:00")
        let expected = reminder(dueAt: date("2025-06-15 08:00"))
        let reminders = [
            expected,
            reminder(dueAt: date("2025-06-16 08:00")),
            reminder(dueAt: date("2025-06-15 18:00"), status: .completed)
        ]

        let result = CareCalendarCalculator.pendingReminders(
            on: selected, reminders: reminders, calendar: calendar
        )
        XCTAssertEqual(result.map(\.id), [expected.id])
    }

    func testCalendarMonthMarksEveryDateWithPendingCount() {
        let reminders = [
            reminder(dueAt: date("2025-06-15 08:00")),
            reminder(dueAt: date("2025-06-15 18:00")),
            reminder(dueAt: date("2025-06-16 08:00")),
            reminder(dueAt: date("2025-06-15 20:00"), status: .completed)
        ]
        var calendar = self.calendar
        calendar.firstWeekday = 1

        let days = CareCalendarCalculator.days(
            forMonthContaining: date("2025-06-01 12:00"),
            reminders: reminders,
            calendar: calendar
        )

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first?.dayNumber, 1, "2025 年 6 月 1 日恰逢周日，不需要上月补位")
        let june15 = days.first { $0.dayNumber == 15 && $0.isInDisplayedMonth }
        XCTAssertEqual(june15?.pendingCount, 2, "完成事项不计入日期标记")
        XCTAssertEqual(days.first { $0.dayNumber == 16 && $0.isInDisplayedMonth }?.pendingCount, 1)
        XCTAssertTrue(days.allSatisfy { $0.isInDisplayedMonth || $0.pendingCount == 0 })
    }

    func testJournalPhotoAssociationMatchesSourceAndUsesStableOrder() {
        let plantID = UUID()
        let journalID = UUID()
        let later = date("2025-06-15 10:00")
        let earlier = date("2025-06-15 09:00")
        let first = photo(plantID: plantID, source: .journal, sourceID: journalID, createdAt: earlier)
        let second = photo(plantID: plantID, source: .journal, sourceID: journalID, createdAt: later)
        let unrelated = photo(plantID: plantID, source: .care, sourceID: journalID, createdAt: earlier)
        let entry = JournalEntry(
            id: UUID(), plantID: plantID, kind: .manual, occurredAt: later,
            title: "手动日志", body: "新叶", sourceType: .manual, sourceID: journalID,
            isManual: true, createdAt: later, updatedAt: later
        )

        let result = JournalPhotoAssociation.photos(for: entry, in: [second, unrelated, first])
        XCTAssertEqual(result.map(\.id), [first.id, second.id])
    }

    private func photo(
        plantID: UUID,
        source: PhotoSourceType,
        sourceID: UUID,
        createdAt: Date
    ) -> PlantPhoto {
        PlantPhoto(
            id: UUID(), plantID: plantID,
            originalRelativePath: "original.jpg", thumbnailRelativePath: "thumbnail.jpg",
            capturedAt: createdAt, caption: nil, sourceType: source, sourceID: sourceID,
            coverCropData: nil, createdAt: createdAt
        )
    }
}
