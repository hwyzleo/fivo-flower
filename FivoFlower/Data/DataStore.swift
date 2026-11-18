import Foundation
import SwiftData

/// 全部 Repository 的本地实现。所有写操作使用同一个 ModelContext，
/// 单次业务操作只调用一次 save()，保持事务边界。
@MainActor
final class FivoDataStore {
    let context: ModelContext
    let imageStore: ImageStore
    var now: () -> Date
    var calendar: Calendar

    private(set) var startupError: String?

    init(
        context: ModelContext,
        imageStore: ImageStore,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = FivoDate.defaultCalendar
    ) {
        self.context = context
        self.imageStore = imageStore
        self.now = now
        self.calendar = calendar
        do {
            try seedBuiltInsIfNeeded()
            try removeDeprecatedBuiltInCareTypes()
            try removeUnsupportedReminders()
        } catch {
            startupError = "初始化基础数据失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Common helpers

    func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw DataError.persistence(error.localizedDescription)
        }
    }

    private func seedBuiltInsIfNeeded() throws {
        let stageCount = try context.fetchCount(FetchDescriptor<GrowthStageRecord>())
        if stageCount == 0 {
            let stages: [(String, String, String)] = [
                (GrowthStageKey.leafRoot, "养叶养根", "leaf"),
                (GrowthStageKey.flowerSpike, "出花梗", "spike"),
                (GrowthStageKey.bloom, "开花", "bloom")
            ]
            for (index, item) in stages.enumerated() {
                context.insert(GrowthStageRecord(
                    key: item.0,
                    name: item.1,
                    isBuiltIn: true,
                    isEnabled: true,
                    sortOrder: index,
                    colorToken: item.2
                ))
            }
        }
        let actionCount = try context.fetchCount(FetchDescriptor<CareActionTypeRecord>())
        if actionCount == 0 {
            for (index, item) in BuiltInCareAction.all.enumerated() {
                context.insert(CareActionTypeRecord(
                    key: item.key,
                    name: item.name,
                    isBuiltIn: true,
                    isEnabled: true,
                    sortOrder: index
                ))
            }
        }
        if stageCount == 0 || actionCount == 0 {
            try save()
        }
    }

    func plantRecord(id: UUID) throws -> PlantRecord {
        var descriptor = FetchDescriptor<PlantRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            throw DataError.notFound("植物档案")
        }
        return record
    }

    func stageName(for key: String) -> String {
        let descriptor = FetchDescriptor<GrowthStageRecord>(predicate: #Predicate { $0.key == key })
        if let record = try? context.fetch(descriptor).first {
            return record.name
        }
        return GrowthStageKey.builtInName(for: key) ?? key
    }

    func stagesByKey() -> [String: GrowthStage] {
        let records = (try? context.fetch(FetchDescriptor<GrowthStageRecord>())) ?? []
        return Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.domain) })
    }

    @discardableResult
    func insertJournal(
        plantID: UUID,
        kind: JournalKind,
        occurredAt: Date,
        title: String,
        body: String,
        sourceType: JournalSourceType?,
        sourceID: UUID?,
        uniqueKey: String? = nil,
        isManual: Bool = false
    ) -> JournalEntryRecord {
        let key: String
        if let uniqueKey {
            key = uniqueKey
        } else if let sourceType, let sourceID {
            key = "\(sourceType.rawValue):\(sourceID.uuidString):\(kind.rawValue)"
        } else {
            key = "\(kind.rawValue):\(UUID().uuidString)"
        }
        let existing = (try? context.fetch(FetchDescriptor<JournalEntryRecord>(predicate: #Predicate { $0.uniqueKey == key }))) ?? []
        if let record = existing.first {
            return record
        }
        let timestamp = now()
        let record = JournalEntryRecord(
            uniqueKey: key,
            plantID: plantID,
            kind: kind,
            occurredAt: occurredAt,
            title: title,
            body: body,
            sourceType: sourceType,
            sourceID: sourceID,
            isManual: isManual,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)
        return record
    }

    func deleteJournal(sourceType: JournalSourceType, sourceID: UUID) {
        let raw = sourceType.rawValue
        let descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.sourceTypeRaw == raw && $0.sourceID == sourceID }
        )
        if let records = try? context.fetch(descriptor) {
            records.forEach { context.delete($0) }
        }
    }

    @discardableResult
    func insertPhoto(
        plantID: UUID,
        payload: ImagePayload,
        source: PhotoSourceType,
        sourceID: UUID?,
        caption: String? = nil,
        logPhoto: Bool
    ) throws -> PlantPhotoRecord {
        let saved = try imageStore.saveImage(data: payload.data)
        let timestamp = now()
        let record = PlantPhotoRecord(
            plantID: plantID,
            originalRelativePath: saved.originalRelativePath,
            thumbnailRelativePath: saved.thumbnailRelativePath,
            capturedAt: payload.capturedAt,
            caption: caption,
            sourceType: source,
            sourceID: sourceID,
            createdAt: timestamp
        )
        context.insert(record)
        if logPhoto {
            insertJournal(
                plantID: plantID,
                kind: .photoAdded,
                occurredAt: timestamp,
                title: "添加照片",
                body: "来源：\(source.title)\(caption.map { "，\($0)" } ?? "")",
                sourceType: .photo,
                sourceID: record.id
            )
        }
        return record
    }

    func deletePhotoFile(_ record: PlantPhotoRecord) {
        try? imageStore.delete(relativePath: record.originalRelativePath)
        try? imageStore.delete(relativePath: record.thumbnailRelativePath)
        if let cover = imageStore.coverRelativePath(forPhotoID: record.id) {
            try? imageStore.delete(relativePath: cover)
        }
    }

    func allRecords<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Domain snapshot for backup

    func snapshot() throws -> BackupDomainSnapshot {
        BackupDomainSnapshot(
            plants: try allRecords(PlantRecord.self).map(\.domain),
            stages: try allRecords(GrowthStageRecord.self).map(\.domain),
            sessions: try allRecords(GrowthSessionRecord.self).map(\.domain),
            photos: try allRecords(PlantPhotoRecord.self).map(\.domain),
            journals: try allRecords(JournalEntryRecord.self).map(\.domain),
            actionTypes: try allRecords(CareActionTypeRecord.self).map(\.domain),
            careLogs: try allRecords(CareLogRecord.self).map(\.domain),
            reminders: try allRecords(CareReminderRecord.self).map(\.domain),
            tools: try allRecords(ToolItemRecord.self).map(\.domain),
            toolPhotos: try allRecords(ToolPhotoRecord.self).map(\.domain),
            stockAdjustments: try allRecords(StockAdjustmentRecord.self).map(\.domain),
            ledgerEntries: try allRecords(LedgerEntryRecord.self).map(\.domain),
            importRecords: try allRecords(OrderImportRecordModel.self).map(\.domain)
        )
    }

    func replaceAll(with snapshot: BackupDomainSnapshot) throws {
        try deleteEverything(seedBuiltIns: false)
        for plant in snapshot.plants {
            context.insert(PlantRecord(
                id: plant.id,
                name: plant.name,
                alias: plant.alias,
                plantCode: plant.plantCode,
                specification: plant.specification,
                acquiredAt: plant.acquiredAt,
                purchasePrice: plant.purchasePrice,
                currency: plant.currency,
                platform: plant.platform,
                storeName: plant.storeName,
                sourceURL: plant.sourceURL,
                medium: plant.medium,
                location: plant.location,
                notes: plant.notes,
                lifeStatus: plant.lifeStatus,
                lifeEventAt: plant.lifeEventAt,
                lifeEventReason: plant.lifeEventReason,
                giftRecipient: plant.giftRecipient,
                coverPhotoID: plant.coverPhotoID,
                createdAt: plant.createdAt,
                updatedAt: plant.updatedAt
            ))
        }
        for stage in snapshot.stages {
            context.insert(GrowthStageRecord(
                key: stage.key,
                name: stage.name,
                isBuiltIn: stage.isBuiltIn,
                isEnabled: stage.isEnabled,
                sortOrder: stage.sortOrder,
                colorToken: stage.colorToken
            ))
        }
        for session in snapshot.sessions {
            context.insert(GrowthSessionRecord(
                id: session.id,
                plantID: session.plantID,
                stageKey: session.stageKey,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                note: session.note,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt
            ))
        }
        for photo in snapshot.photos {
            context.insert(PlantPhotoRecord(
                id: photo.id,
                plantID: photo.plantID,
                originalRelativePath: photo.originalRelativePath,
                thumbnailRelativePath: photo.thumbnailRelativePath,
                capturedAt: photo.capturedAt,
                caption: photo.caption,
                sourceType: photo.sourceType,
                sourceID: photo.sourceID,
                coverCropData: photo.coverCropData,
                createdAt: photo.createdAt
            ))
        }
        for journal in snapshot.journals {
            context.insert(JournalEntryRecord(
                id: journal.id,
                uniqueKey: "restore:\(journal.id.uuidString)",
                plantID: journal.plantID,
                kind: journal.kind,
                occurredAt: journal.occurredAt,
                title: journal.title,
                body: journal.body,
                sourceType: journal.sourceType,
                sourceID: journal.sourceID,
                isManual: journal.isManual,
                createdAt: journal.createdAt,
                updatedAt: journal.updatedAt
            ))
        }
        for action in snapshot.actionTypes {
            context.insert(CareActionTypeRecord(
                id: action.id,
                key: action.key,
                name: action.name,
                isBuiltIn: action.isBuiltIn,
                isEnabled: action.isEnabled,
                sortOrder: action.sortOrder
            ))
        }
        for log in snapshot.careLogs {
            context.insert(CareLogRecord(
                id: log.id,
                plantID: log.plantID,
                actionTypeID: log.actionTypeID,
                actionNameSnapshot: log.actionNameSnapshot,
                occurredAt: log.occurredAt,
                note: log.note,
                dosage: log.dosage,
                unit: log.unit,
                batchID: log.batchID,
                createdAt: log.createdAt,
                updatedAt: log.updatedAt
            ))
        }
        for reminder in snapshot.reminders {
            context.insert(CareReminderRecord(
                id: reminder.id,
                plantID: reminder.plantID,
                actionTypeID: reminder.actionTypeID,
                actionNameSnapshot: reminder.actionNameSnapshot,
                title: reminder.title,
                dueAt: reminder.dueAt,
                recurrence: reminder.recurrence,
                status: reminder.status,
                completedAt: reminder.completedAt,
                notificationID: nil,
                groupID: reminder.groupID,
                createdAt: reminder.createdAt,
                updatedAt: reminder.updatedAt
            ))
        }
        for tool in snapshot.tools {
            context.insert(ToolItemRecord(
                id: tool.id,
                name: tool.name,
                category: tool.category,
                brand: tool.brand,
                specification: tool.specification,
                purchasedAt: tool.purchasedAt,
                purchasePrice: tool.purchasePrice,
                quantity: tool.quantity,
                location: tool.location,
                photoRelativePath: tool.photoRelativePath,
                notes: tool.notes,
                isConsumable: tool.isConsumable,
                stock: tool.stock,
                stockUnit: tool.stockUnit,
                lowStockThreshold: tool.lowStockThreshold,
                lowStockEnabled: tool.lowStockEnabled,
                isDevice: tool.isDevice,
                isPoweredOn: tool.isPoweredOn,
                createdAt: tool.createdAt,
                updatedAt: tool.updatedAt
            ))
        }
        for photo in snapshot.toolPhotos {
            context.insert(ToolPhotoRecord(
                id: photo.id,
                toolID: photo.toolID,
                originalRelativePath: photo.originalRelativePath,
                thumbnailRelativePath: photo.thumbnailRelativePath,
                capturedAt: photo.capturedAt,
                caption: photo.caption,
                createdAt: photo.createdAt
            ))
        }
        for adjustment in snapshot.stockAdjustments {
            context.insert(StockAdjustmentRecord(
                id: adjustment.id,
                toolID: adjustment.toolID,
                mode: adjustment.mode,
                delta: adjustment.delta,
                resultingStock: adjustment.resultingStock,
                occurredAt: adjustment.occurredAt,
                note: adjustment.note,
                createdAt: adjustment.createdAt
            ))
        }
        for entry in snapshot.ledgerEntries {
            context.insert(LedgerEntryRecord(
                id: entry.id,
                kind: entry.kind,
                title: entry.title,
                category: entry.category,
                amount: entry.amount,
                currency: entry.currency,
                occurredAt: entry.occurredAt,
                platform: entry.platform,
                storeName: entry.storeName,
                plantID: entry.plantID,
                toolID: entry.toolID,
                note: entry.note,
                sourceType: entry.sourceType,
                sourceID: entry.sourceID,
                relatedEntryID: entry.relatedEntryID,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            ))
        }
        for record in snapshot.importRecords {
            let ids = (try? JSONEncoder().encode(record.attachmentIDs)) ?? Data()
            context.insert(OrderImportRecordModel(
                id: record.id,
                attachmentIDsJSON: String(data: ids, encoding: .utf8) ?? "[]",
                rawOCRText: record.rawOCRText,
                recognizedDraftJSON: record.recognizedDraftJSON,
                status: record.status,
                orderNumber: record.orderNumber,
                failureMessage: record.failureMessage,
                importedPlantID: record.importedPlantID,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            ))
        }
        try save()
        // 恢复内置定义缺失时的兜底
        try seedBuiltInsIfNeeded()
        // 旧备份可能包含已下线的内置养护类型
        try removeDeprecatedBuiltInCareTypes()
    }

    func deleteEverything(seedBuiltIns: Bool = true) throws {
        try context.delete(model: PlantRecord.self)
        try context.delete(model: GrowthSessionRecord.self)
        try context.delete(model: PlantPhotoRecord.self)
        try context.delete(model: OrderAttachmentRecord.self)
        try context.delete(model: JournalEntryRecord.self)
        try context.delete(model: CareLogRecord.self)
        try context.delete(model: CareReminderRecord.self)
        try context.delete(model: ToolItemRecord.self)
        try context.delete(model: ToolPhotoRecord.self)
        try context.delete(model: StockAdjustmentRecord.self)
        try context.delete(model: LedgerEntryRecord.self)
        try context.delete(model: OrderImportRecordModel.self)
        try context.delete(model: GrowthStageRecord.self)
        try context.delete(model: CareActionTypeRecord.self)
        try save()
        if seedBuiltIns {
            try seedBuiltInsIfNeeded()
        }
    }

    func clearAllData(removeMedia: Bool = true) throws {
        try deleteEverything()
        if removeMedia {
            try imageStore.deleteAll()
        }
    }
}

struct BackupDomainSnapshot {
    var plants: [Plant]
    var stages: [GrowthStage]
    var sessions: [GrowthSession]
    var photos: [PlantPhoto]
    var journals: [JournalEntry]
    var actionTypes: [CareActionType]
    var careLogs: [CareLog]
    var reminders: [CareReminder]
    var tools: [ToolItem]
    var toolPhotos: [ToolPhoto]
    var stockAdjustments: [StockAdjustment]
    var ledgerEntries: [LedgerEntry]
    var importRecords: [OrderImportRecord]
}
