import Foundation
import SwiftData

extension FivoDataStore: CareRepository {

    func actionTypes(includeDisabled: Bool) throws -> [CareActionType] {
        let descriptor = FetchDescriptor<CareActionTypeRecord>(
            sortBy: [SortDescriptor(\CareActionTypeRecord.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
            .filter { includeDisabled || $0.isEnabled }
            .map(\.domain)
    }

    func addActionType(name: String) throws -> CareActionType {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DataError.validation("请填写养护类型名称")
        }
        let existing = try actionTypes(includeDisabled: true)
        guard !existing.contains(where: { $0.name == trimmed }) else {
            throw DataError.validation("已存在同名养护类型")
        }
        let record = CareActionTypeRecord(
            key: UUID().uuidString,
            name: trimmed,
            isBuiltIn: false,
            isEnabled: true,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1
        )
        context.insert(record)
        try save()
        return record.domain
    }

    func renameActionType(id: UUID, name: String) throws {
        let record = try actionTypeRecord(id: id)
        guard !record.isBuiltIn else {
            throw DataError.validation("内置养护类型不支持重命名")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DataError.validation("请填写养护类型名称")
        }
        record.name = trimmed
        try save()
    }

    func setActionTypeEnabled(id: UUID, enabled: Bool) throws {
        let record = try actionTypeRecord(id: id)
        record.isEnabled = enabled
        try save()
    }

    /// 按传入的 id 顺序重排养护类型；未传入的记录保持原有相对顺序排在末尾。
    func reorderActionTypes(ids: [UUID]) throws {
        var remaining = try context.fetch(FetchDescriptor<CareActionTypeRecord>(
            sortBy: [SortDescriptor(\CareActionTypeRecord.sortOrder, order: .forward)]
        ))
        var ordered: [CareActionTypeRecord] = []
        for id in ids {
            if let index = remaining.firstIndex(where: { $0.id == id }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        ordered.append(contentsOf: remaining)
        for (index, record) in ordered.enumerated() where record.sortOrder != index {
            record.sortOrder = index
        }
        try save()
    }

    /// 清理已下线（例如「其他」）的内置养护类型，历史记录保留名称快照。
    func removeDeprecatedBuiltInCareTypes() throws {
        let records = try context.fetch(FetchDescriptor<CareActionTypeRecord>())
        let deprecated = records.filter { $0.isBuiltIn && BuiltInCareAction.deprecatedKeys.contains($0.key) }
        guard !deprecated.isEmpty else { return }
        let deprecatedIDs = Set(deprecated.map(\.id))

        let timestamp = now()
        for log in try context.fetch(FetchDescriptor<CareLogRecord>()) {
            guard let actionTypeID = log.actionTypeID, deprecatedIDs.contains(actionTypeID) else { continue }
            log.actionTypeID = nil
            log.updatedAt = timestamp
        }
        for reminder in try context.fetch(FetchDescriptor<CareReminderRecord>()) {
            guard let actionTypeID = reminder.actionTypeID, deprecatedIDs.contains(actionTypeID) else { continue }
            reminder.actionTypeID = nil
            reminder.updatedAt = timestamp
        }
        for record in deprecated {
            context.delete(record)
        }
        try save()

        try reorderActionTypes(ids: try actionTypes(includeDisabled: true).map(\.id))
    }

    func deleteActionType(id: UUID) throws {
        let record = try actionTypeRecord(id: id)
        guard !record.isBuiltIn else {
            throw DataError.validation("内置养护类型不能删除，可停用")
        }
        let logs = try context.fetch(FetchDescriptor<CareLogRecord>())
        for log in logs where log.actionTypeID == id {
            log.actionTypeID = nil
            log.updatedAt = now()
        }
        let reminders = try context.fetch(FetchDescriptor<CareReminderRecord>())
        for reminder in reminders where reminder.actionTypeID == id {
            reminder.actionTypeID = nil
            reminder.updatedAt = now()
        }
        context.delete(record)
        try save()
    }

    func recentLogCount(plantID: UUID, limit: Int) throws -> Int {
        min(try careLogRecords(plantID: plantID).count, limit)
    }

    func logs(plantID: UUID?) throws -> [CareLog] {
        let records = try careLogRecords(plantID: plantID)
        return records
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func recordCare(_ draft: CareRecordDraft) throws -> CareBatchResult {
        guard !draft.plantIDs.isEmpty else {
            throw DataError.validation("请至少选择一株植物")
        }
        guard !FivoDate.isFutureDay(draft.occurredAt, now: now(), calendar: calendar) else {
            throw DataError.validation("养护时间不能晚于今天")
        }
        let action: CareActionType
        if let actionTypeID = draft.actionTypeID {
            action = try actionTypeRecord(id: actionTypeID).domain
        } else {
            throw DataError.validation("请选择养护动作")
        }
        let timestamp = now()
        let batchID = draft.plantIDs.count > 1 ? UUID() : nil
        var logs: [CareLogRecord] = []
        let dosage = PlantValidator.normalized(draft.dosage)
        let unit = PlantValidator.normalized(draft.unit)
        let note = PlantValidator.normalized(draft.note)

        do {
            for plantID in draft.plantIDs {
                _ = try plantRecord(id: plantID)
                let log = CareLogRecord(
                    plantID: plantID,
                    actionTypeID: action.id,
                    actionNameSnapshot: action.name,
                    occurredAt: draft.occurredAt,
                    note: note,
                    dosage: dosage,
                    unit: unit,
                    batchID: batchID,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
                context.insert(log)
                logs.append(log)

                var body = "\(action.name)"
                if let dosage, let unit {
                    body += "，用量 \(dosage) \(unit)"
                } else if let dosage {
                    body += "，用量 \(dosage)"
                }
                if let note {
                    body += "，备注：\(note)"
                }
                insertJournal(
                    plantID: plantID,
                    kind: .care,
                    occurredAt: draft.occurredAt,
                    title: action.name,
                    body: body,
                    sourceType: .careLog,
                    sourceID: log.id
                )
                for payload in draft.photos {
                    _ = try insertPhoto(
                        plantID: plantID,
                        payload: payload,
                        source: .care,
                        sourceID: log.id,
                        logPhoto: false
                    )
                }
                try completePendingReminderForManualCare(
                    plantID: plantID,
                    action: action,
                    occurredAt: draft.occurredAt,
                    timestamp: timestamp
                )
                let plant = try plantRecord(id: plantID)
                plant.updatedAt = timestamp
            }
            try save()
        } catch {
            throw error
        }
        return CareBatchResult(logs: logs.map(\.domain), batchID: batchID ?? UUID())
    }

    func actionTypeRecord(id: UUID) throws -> CareActionTypeRecord {
        let descriptor = FetchDescriptor<CareActionTypeRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw DataError.notFound("养护类型")
        }
        return record
    }

    func careLogRecords(plantID: UUID?) throws -> [CareLogRecord] {
        if let plantID {
            let descriptor = FetchDescriptor<CareLogRecord>(predicate: #Predicate { $0.plantID == plantID })
            return try context.fetch(descriptor)
        }
        return try context.fetch(FetchDescriptor<CareLogRecord>())
    }
}

extension FivoDataStore: ReminderRepository {

    func reminders() throws -> [CareReminder] {
        try context.fetch(FetchDescriptor<CareReminderRecord>())
            .sorted { $0.dueAt < $1.dueAt }
            .map(\.domain)
    }

    func pendingReminderCount() throws -> Int {
        try context.fetch(FetchDescriptor<CareReminderRecord>())
            .filter { $0.statusRaw == ReminderStatus.pending.rawValue }
            .count
    }

    func createReminders(_ draft: ReminderDraft) throws -> [CareReminder] {
        guard !draft.plantIDs.isEmpty else {
            throw DataError.validation("请至少选择一株植物")
        }
        let action = draft.actionTypeID.flatMap { try? actionTypeRecord(id: $0).domain }
        let baseTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = baseTitle.isEmpty ? (action?.name ?? "养护周期") : baseTitle
        let timestamp = now()
        let groupID = draft.plantIDs.count > 1 ? UUID() : nil
        var created: [CareReminderRecord] = []
        for plantID in draft.plantIDs {
            _ = try plantRecord(id: plantID)
            let reminderID = UUID()
            let record = CareReminderRecord(
                id: reminderID,
                plantID: plantID,
                actionTypeID: action?.id,
                actionNameSnapshot: action?.name,
                title: resolvedTitle,
                dueAt: draft.dueAt,
                recurrence: draft.recurrence,
                status: .pending,
                notificationID: "care-reminder-\(reminderID.uuidString)",
                groupID: groupID,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            context.insert(record)
            created.append(record)
        }
        try save()
        return created.map(\.domain)
    }

    func updateReminder(id: UUID, draft: ReminderDraft) throws -> CareReminder {
        let record = try reminderRecord(id: id)
        guard record.statusRaw == ReminderStatus.pending.rawValue else {
            throw DataError.validation("已完成的周期待办不能修改")
        }
        guard draft.plantIDs == [record.plantID] else {
            throw DataError.validation("修改周期时不能更换植物")
        }
        let action = draft.actionTypeID.flatMap { try? actionTypeRecord(id: $0).domain }
        let baseTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = try latestCareDate(
            plantID: record.plantID,
            actionTypeID: record.actionTypeID,
            actionName: record.actionNameSnapshot ?? record.title
        ) ?? record.createdAt
        guard let nextDue = draft.recurrence.nextDue(after: anchor, calendar: calendar) else {
            throw DataError.validation("无法计算下一次待办时间")
        }

        record.actionTypeID = action?.id ?? record.actionTypeID
        record.actionNameSnapshot = action?.name ?? record.actionNameSnapshot
        record.title = baseTitle.isEmpty ? (action?.name ?? record.title) : baseTitle
        record.dueAt = nextDue
        record.recurrenceRaw = draft.recurrence.rawValue
        record.updatedAt = now()
        try save()
        return record.domain
    }

    func completeReminder(id: UUID, at date: Date, createCareRecord: Bool) throws -> CareReminder? {
        let record = try reminderRecord(id: id)
        guard record.statusRaw == ReminderStatus.pending.rawValue else {
            return nil
        }
        let timestamp = now()
        record.statusRaw = ReminderStatus.completed.rawValue
        record.completedAt = date
        record.updatedAt = timestamp

        if createCareRecord {
            let log = CareLogRecord(
                plantID: record.plantID,
                actionTypeID: record.actionTypeID,
                actionNameSnapshot: record.actionNameSnapshot ?? record.title,
                occurredAt: date,
                note: "完成周期待办：\(record.title)",
                createdAt: timestamp,
                updatedAt: timestamp
            )
            context.insert(log)
            insertJournal(
                plantID: record.plantID,
                kind: .care,
                occurredAt: date,
                title: record.actionNameSnapshot ?? record.title,
                body: "完成周期待办：\(record.title)",
                sourceType: .careLog,
                sourceID: log.id
            )
        }

        let next = makeNextReminder(from: record, anchor: date, timestamp: timestamp)
        try save()
        return next?.domain
    }

    func deleteReminder(id: UUID) throws {
        let record = try reminderRecord(id: id)
        context.delete(record)
        try save()
    }

    // MARK: - Helpers

    func reminderRecord(id: UUID) throws -> CareReminderRecord {
        let descriptor = FetchDescriptor<CareReminderRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw DataError.notFound("提醒")
        }
        return record
    }

    func reminderRecords(plantID: UUID) throws -> [CareReminderRecord] {
        let descriptor = FetchDescriptor<CareReminderRecord>(predicate: #Predicate { $0.plantID == plantID })
        return try context.fetch(descriptor)
    }

    private func makeNextReminder(
        from record: CareReminderRecord,
        anchor: Date,
        timestamp: Date
    ) -> CareReminderRecord? {
        guard let recurrence = ReminderRecurrence(rawValue: record.recurrenceRaw),
              let nextDue = recurrence.nextDue(after: anchor, calendar: calendar) else {
            return nil
        }
        let reminderID = UUID()
        let next = CareReminderRecord(
            id: reminderID,
            plantID: record.plantID,
            actionTypeID: record.actionTypeID,
            actionNameSnapshot: record.actionNameSnapshot,
            title: record.title,
            dueAt: nextDue,
            recurrence: recurrence,
            status: .pending,
            notificationID: "care-reminder-\(reminderID.uuidString)",
            groupID: record.groupID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(next)
        return next
    }

    private func latestCareDate(plantID: UUID, actionTypeID: UUID?, actionName: String) throws -> Date? {
        try careLogRecords(plantID: plantID)
            .filter { log in
                if let actionTypeID, let logActionID = log.actionTypeID {
                    return logActionID == actionTypeID
                }
                return log.actionNameSnapshot == actionName
            }
            .map(\.occurredAt)
            .max()
    }

    private func completePendingReminderForManualCare(
        plantID: UUID,
        action: CareActionType,
        occurredAt: Date,
        timestamp: Date
    ) throws {
        let candidates = try reminderRecords(plantID: plantID)
            .filter { record in
                guard record.statusRaw == ReminderStatus.pending.rawValue else { return false }
                if let reminderActionID = record.actionTypeID {
                    return reminderActionID == action.id
                }
                return (record.actionNameSnapshot ?? record.title) == action.name
            }
            .sorted { $0.dueAt < $1.dueAt }
        guard let current = candidates.first else { return }

        current.statusRaw = ReminderStatus.completed.rawValue
        current.completedAt = occurredAt
        current.updatedAt = timestamp
        _ = makeNextReminder(from: current, anchor: occurredAt, timestamp: timestamp)
    }

    func removeUnsupportedReminders() throws {
        let records = try context.fetch(FetchDescriptor<CareReminderRecord>())
        var removed = false
        for record in records where ReminderRecurrence(rawValue: record.recurrenceRaw) == nil {
            context.delete(record)
            removed = true
        }
        if removed {
            try save()
        }
    }
}
