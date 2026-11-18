import Foundation
import SwiftData

extension FivoDataStore: GrowthRepository {

    func stages(includeDisabled: Bool) throws -> [GrowthStage] {
        let descriptor = FetchDescriptor<GrowthStageRecord>(
            sortBy: [SortDescriptor(\GrowthStageRecord.sortOrder, order: .forward)]
        )
        return try context.fetch(descriptor)
            .filter { includeDisabled || $0.isEnabled }
            .map(\.domain)
    }

    func stage(key: String) throws -> GrowthStage? {
        try stageRecord(key: key)?.domain
    }

    func addStage(name: String) throws -> GrowthStage {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DataError.validation("请填写状态名称")
        }
        let existing = try stages(includeDisabled: true)
        guard !existing.contains(where: { $0.name == trimmed }) else {
            throw DataError.validation("已存在同名状态")
        }
        let record = GrowthStageRecord(
            key: UUID().uuidString,
            name: trimmed,
            isBuiltIn: false,
            isEnabled: true,
            sortOrder: (existing.map(\.sortOrder).max() ?? 0) + 1,
            colorToken: "custom"
        )
        context.insert(record)
        try save()
        return record.domain
    }

    func renameStage(key: String, name: String) throws {
        guard let record = try stageRecord(key: key) else {
            throw DataError.notFound("生长状态")
        }
        guard !record.isBuiltIn else {
            throw DataError.validation("内置状态不支持重命名")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DataError.validation("请填写状态名称")
        }
        record.name = trimmed
        try save()
    }

    func setStageEnabled(key: String, enabled: Bool) throws {
        guard let record = try stageRecord(key: key) else {
            throw DataError.notFound("生长状态")
        }
        if !enabled, record.isBuiltIn {
            let sessions = try context.fetch(FetchDescriptor<GrowthSessionRecord>())
            let ongoingBuiltIn = sessions.filter { $0.stageKey == key && $0.endedAt == nil }
            if !ongoingBuiltIn.isEmpty {
                throw DataError.validation("仍有植物处于该状态，不能停用")
            }
        }
        record.isEnabled = enabled
        try save()
    }

    func deleteStage(key: String) throws {
        guard let record = try stageRecord(key: key) else {
            throw DataError.notFound("生长状态")
        }
        guard !record.isBuiltIn else {
            throw DataError.validation("内置状态不能删除，可停用")
        }
        let used = try context.fetch(FetchDescriptor<GrowthSessionRecord>())
            .contains { $0.stageKey == key }
        guard !used else {
            throw DataError.validation("该状态已有历史记录，只能停用")
        }
        context.delete(record)
        try save()
    }

    func sessions(plantID: UUID) throws -> [GrowthSession] {
        try sessionRecords(plantID: plantID)
            .sorted { $0.startedAt > $1.startedAt }
            .map(\.domain)
    }

    func currentSession(plantID: UUID) throws -> GrowthSession? {
        try sessionRecords(plantID: plantID)
            .filter { $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }?
            .domain
    }

    func switchStage(
        plantID: UUID,
        to stageKey: String,
        at date: Date,
        note: String,
        photos: [ImagePayload]
    ) throws {
        let plant = try plantRecord(id: plantID)
        guard plant.lifeStatusRaw == PlantLifeStatus.active.rawValue else {
            throw DataError.validation("已归档的植物不能切换生长状态，请先恢复档案")
        }
        guard let stage = try stageRecord(key: stageKey), stage.isEnabled else {
            throw DataError.validation("该生长状态不可用")
        }
        guard !FivoDate.isFutureDay(date, now: now(), calendar: calendar) else {
            throw GrowthSessionError.startInFuture
        }
        let timestamp = now()
        let records = try sessionRecords(plantID: plantID)
        let ongoing = records.filter { $0.endedAt == nil }
        if let current = ongoing.first {
            guard date >= current.startedAt else {
                throw DataError.validation("切换日期不能早于当前状态的开始日期")
            }
            current.endedAt = date
            current.updatedAt = timestamp
        }
        let conflicts = records.contains { session in
            guard session.endedAt == nil || session.id == ongoing.first?.id else {
                guard let endedAt = session.endedAt else { return false }
                return date < endedAt && session.startedAt < endedAt && session.startedAt >= date
            }
            return false
        }
        if conflicts {
            throw GrowthSessionError.overlap
        }
        let session = GrowthSessionRecord(
            plantID: plantID,
            stageKey: stageKey,
            startedAt: date,
            note: PlantValidator.normalized(note),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(session)
        plant.updatedAt = timestamp

        var body = "\(FivoDate.dateTime(date)) 切换为\(stage.name)"
        if let normalizedNote = PlantValidator.normalized(note) {
            body += "，备注：\(normalizedNote)"
        }
        insertJournal(
            plantID: plantID,
            kind: .growthChanged,
            occurredAt: date,
            title: "切换为\(stage.name)",
            body: body,
            sourceType: .growthSession,
            sourceID: session.id
        )
        do {
            for payload in photos {
                _ = try insertPhoto(
                    plantID: plantID,
                    payload: payload,
                    source: .growth,
                    sourceID: session.id,
                    logPhoto: false
                )
            }
            try save()
        } catch {
            throw error
        }
    }

    func updateSession(id: UUID, startedAt: Date, endedAt: Date?, note: String) throws {
        let descriptor = FetchDescriptor<GrowthSessionRecord>(predicate: #Predicate { $0.id == id })
        guard let session = try context.fetch(descriptor).first else {
            throw DataError.notFound("状态记录")
        }
        let currentTime = now()
        if FivoDate.startOfDay(startedAt) > FivoDate.startOfDay(currentTime) {
            throw GrowthSessionError.startInFuture
        }
        if let endedAt {
            guard endedAt >= startedAt else { throw GrowthSessionError.endBeforeStart }
            guard !FivoDate.isFutureDay(endedAt, now: currentTime, calendar: calendar) else {
                throw GrowthSessionError.endInFuture
            }
        }
        let siblings = try sessionRecords(plantID: session.plantID).filter { $0.id != session.id }
        if endedAt == nil, siblings.contains(where: { $0.endedAt == nil }) {
            throw GrowthSessionError.overlap
        }
        let newStart = startedAt
        let newEnd = endedAt ?? Date.distantFuture
        let overlaps = siblings.contains { other in
            let otherStart = other.startedAt
            let otherEnd = other.endedAt ?? Date.distantFuture
            return newStart < otherEnd && otherStart < newEnd
        }
        if overlaps {
            throw GrowthSessionError.overlap
        }
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.note = PlantValidator.normalized(note)
        session.updatedAt = currentTime
        try save()
    }

    func statistics(plantID: UUID) throws -> PlantStatistics {
        let sessions = try sessionRecords(plantID: plantID).map(\.domain)
        return PlantStatisticsService(calendar: calendar).statistics(sessions: sessions, now: now())
    }

    // MARK: - Shared fetches

    func sessionRecords(plantID: UUID) throws -> [GrowthSessionRecord] {
        let descriptor = FetchDescriptor<GrowthSessionRecord>(predicate: #Predicate { $0.plantID == plantID })
        return try context.fetch(descriptor)
    }

    func currentSessionMap() throws -> [UUID: GrowthSession] {
        let records = try context.fetch(FetchDescriptor<GrowthSessionRecord>())
        var result: [UUID: GrowthSession] = [:]
        for record in records where record.endedAt == nil {
            if let existing = result[record.plantID], existing.startedAt > record.startedAt {
                continue
            }
            result[record.plantID] = record.domain
        }
        return result
    }
}
