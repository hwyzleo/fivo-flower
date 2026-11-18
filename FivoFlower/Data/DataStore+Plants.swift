import Foundation
import SwiftData

extension FivoDataStore: PlantRepository {

    func fetchPlants() throws -> [Plant] {
        let descriptor = FetchDescriptor<PlantRecord>(
            sortBy: [SortDescriptor(\PlantRecord.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.domain)
    }

    func plant(id: UUID) throws -> Plant? {
        try? plantRecord(id: id).domain
    }

    func createPlant(draft: PlantDraft, options: PlantCreationOptions) throws -> Plant {
        let errors = PlantValidator.validate(draft, now: now())
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        if let initialStageStartedAt = options.initialStageStartedAt,
           FivoDate.isFutureDay(initialStageStartedAt, now: now(), calendar: calendar) {
            throw DataError.validation("初始生长状态开始日期不能晚于今天")
        }
        let timestamp = now()
        let initialStageStartedAt = options.initialStageStartedAt.map {
            FivoDate.startOfDay($0, calendar: calendar)
        } ?? timestamp
        let record = PlantRecord(
            name: draft.trimmedName,
            alias: PlantValidator.normalized(draft.alias),
            plantCode: PlantValidator.normalized(draft.plantCode),
            specification: PlantValidator.normalized(draft.specification),
            acquiredAt: draft.acquiredAt,
            purchasePrice: draft.purchasePrice,
            platform: PlantValidator.normalized(draft.platform),
            storeName: PlantValidator.normalized(draft.storeName),
            sourceURL: PlantValidator.normalized(draft.sourceURL),
            medium: PlantValidator.normalized(draft.medium),
            location: PlantValidator.normalized(draft.location),
            notes: PlantValidator.normalized(draft.notes),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)

        let stageKey = (try? stageRecord(key: options.initialStageKey)) != nil
            ? options.initialStageKey
            : GrowthStageKey.leafRoot
        context.insert(GrowthSessionRecord(
            plantID: record.id,
            stageKey: stageKey,
            startedAt: initialStageStartedAt,
            createdAt: timestamp,
            updatedAt: timestamp
        ))

        let isImport = options.importRecordID != nil
        insertJournal(
            plantID: record.id,
            kind: isImport ? .orderImported : .plantCreated,
            occurredAt: timestamp,
            title: isImport ? "订单导入" : "新建档案",
            body: options.initialJournalBody ?? "创建了「\(record.name)」",
            sourceType: .plant,
            sourceID: record.id
        )

        var savedPhotos: [PlantPhotoRecord] = []
        do {
            if let cover = options.coverPhoto {
                let photo = try insertPhoto(
                    plantID: record.id,
                    payload: cover,
                    source: .plant,
                    sourceID: record.id,
                    caption: "封面",
                    logPhoto: false
                )
                record.coverPhotoID = photo.id
                savedPhotos.append(photo)
            }
            for (index, attachment) in options.orderAttachments.enumerated() {
                let photo = try insertPhoto(
                    plantID: record.id,
                    payload: attachment,
                    source: .order,
                    sourceID: options.importRecordID,
                    caption: options.orderAttachments.count > 1 ? "订单截图 \(index + 1)" : "订单截图",
                    logPhoto: false
                )
                savedPhotos.append(photo)
            }

            if let ledgerDraft = options.ledgerDraft,
               ledgerDraft.generateLedger,
               let amount = ledgerDraft.amount,
               amount > 0 {
                let detail = purchaseLedgerDraft(
                    base: ledgerDraft,
                    fallbackPlatform: record.platform,
                    fallbackStore: record.storeName
                )
                insertPurchaseLedger(
                    draft: detail,
                    title: "植物采购：\(record.name)",
                    plantID: record.id,
                    toolID: nil,
                    sourceType: .plant,
                    sourceID: record.id,
                    timestamp: timestamp
                )
            }

            if let importRecordID = options.importRecordID {
                try markImportCompleted(id: importRecordID, plantID: record.id)
            }

            try save()
        } catch {
            for photo in savedPhotos {
                deletePhotoFile(photo)
            }
            throw error
        }
        return record.domain
    }

    func updatePlant(id: UUID, draft: PlantDraft, syncPurchaseLedger: Bool) throws -> Plant {
        let errors = PlantValidator.validate(draft, now: now())
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        let record = try plantRecord(id: id)
        let timestamp = now()

        var changes: [String] = []
        func update(_ label: String, oldValue: String?, newValue: String?, apply: () -> Void) {
            if (oldValue ?? "") != (newValue ?? "") {
                changes.append(label)
                apply()
            }
        }

        update("品种名称", oldValue: record.name, newValue: draft.trimmedName) { record.name = draft.trimmedName }
        update("别名", oldValue: record.alias, newValue: PlantValidator.normalized(draft.alias)) {
            record.alias = PlantValidator.normalized(draft.alias)
        }
        update("植物编号", oldValue: record.plantCode, newValue: PlantValidator.normalized(draft.plantCode)) {
            record.plantCode = PlantValidator.normalized(draft.plantCode)
        }
        update("规格", oldValue: record.specification, newValue: PlantValidator.normalized(draft.specification)) {
            record.specification = PlantValidator.normalized(draft.specification)
        }
        if record.acquiredAt != draft.acquiredAt {
            changes.append("购买日期")
            record.acquiredAt = draft.acquiredAt
        }
        if record.purchasePrice != draft.purchasePrice {
            changes.append("入手价")
            record.purchasePrice = draft.purchasePrice
        }
        update("平台", oldValue: record.platform, newValue: PlantValidator.normalized(draft.platform)) {
            record.platform = PlantValidator.normalized(draft.platform)
        }
        update("店名", oldValue: record.storeName, newValue: PlantValidator.normalized(draft.storeName)) {
            record.storeName = PlantValidator.normalized(draft.storeName)
        }
        update("来源链接", oldValue: record.sourceURL, newValue: PlantValidator.normalized(draft.sourceURL)) {
            record.sourceURL = PlantValidator.normalized(draft.sourceURL)
        }
        update("植料", oldValue: record.medium, newValue: PlantValidator.normalized(draft.medium)) {
            record.medium = PlantValidator.normalized(draft.medium)
        }
        update("摆放位置", oldValue: record.location, newValue: PlantValidator.normalized(draft.location)) {
            record.location = PlantValidator.normalized(draft.location)
        }
        update("备注", oldValue: record.notes, newValue: PlantValidator.normalized(draft.notes)) {
            record.notes = PlantValidator.normalized(draft.notes)
        }

        if !changes.isEmpty {
            record.updatedAt = timestamp
            insertJournal(
                plantID: record.id,
                kind: .plantUpdated,
                occurredAt: timestamp,
                title: "资料修改",
                body: "修改了：\(changes.joined(separator: "、"))",
                sourceType: .plant,
                sourceID: record.id,
                uniqueKey: "plant:\(record.id.uuidString):plantUpdated:\(UUID().uuidString)"
            )
        }

        if syncPurchaseLedger, let price = draft.purchasePrice {
            syncAutoPurchaseLedger(plantID: record.id, amount: price, timestamp: timestamp)
        }

        try save()
        return record.domain
    }

    func duplicatePlant(id: UUID) throws -> Plant {
        let source = try plantRecord(id: id)
        let timestamp = now()
        let record = PlantRecord(
            name: "\(source.name)（副本）",
            alias: source.alias,
            plantCode: nil,
            specification: source.specification,
            acquiredAt: source.acquiredAt,
            purchasePrice: nil,
            currency: source.currency,
            platform: source.platform,
            storeName: source.storeName,
            sourceURL: source.sourceURL,
            medium: source.medium,
            location: source.location,
            notes: source.notes,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)
        context.insert(GrowthSessionRecord(
            plantID: record.id,
            stageKey: GrowthStageKey.leafRoot,
            startedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        ))
        insertJournal(
            plantID: record.id,
            kind: .plantCreated,
            occurredAt: timestamp,
            title: "复制档案",
            body: "从「\(source.name)」复制；未复制日志、养护、状态历史和账目，入手价已清空。",
            sourceType: .plant,
            sourceID: record.id
        )
        try save()
        return record.domain
    }

    func setLifeStatus(
        plantID: UUID,
        status: PlantLifeStatus,
        date: Date,
        reason: String?,
        recipient: String?
    ) throws {
        guard status == .dead || status == .gifted else {
            throw DataError.validation("只能标记为死亡或赠送")
        }
        let record = try plantRecord(id: plantID)
        let draft = LifeEventDraft(
            status: status,
            date: date,
            reason: reason ?? "",
            recipient: recipient ?? ""
        )
        let errors = LifeEventValidator.errors(draft: draft, plant: record.domain, now: now())
        if let first = errors.first {
            throw DataError.validation(first)
        }
        let timestamp = now()
        record.lifeStatusRaw = status.rawValue
        record.lifeEventAt = FivoDate.startOfDay(date)
        record.lifeEventReason = PlantValidator.normalized(reason ?? "")
        record.giftRecipient = PlantValidator.normalized(recipient ?? "")
        record.updatedAt = timestamp

        let sessions = try sessionRecords(plantID: plantID).filter { $0.endedAt == nil }
        for session in sessions {
            let end = max(FivoDate.startOfDay(date), session.startedAt)
            session.endedAt = min(end, timestamp)
            session.updatedAt = timestamp
        }

        var body = "\(FivoDate.day(date)) 标记为\(status.title)"
        if let reason = PlantValidator.normalized(reason ?? "") {
            body += "，原因：\(reason)"
        }
        if let recipient = PlantValidator.normalized(recipient ?? "") {
            body += "，接收人：\(recipient)"
        }
        insertJournal(
            plantID: plantID,
            kind: .lifeStatusChanged,
            occurredAt: date,
            title: status == .dead ? "标记为死亡" : "标记为赠送",
            body: body,
            sourceType: .lifeEvent,
            sourceID: plantID,
            uniqueKey: "lifeEvent:\(plantID.uuidString):\(status.rawValue):\(date.timeIntervalSince1970)"
        )
        try save()
    }

    func restore(plantID: UUID) throws {
        let record = try plantRecord(id: plantID)
        guard record.lifeStatusRaw != PlantLifeStatus.active.rawValue else { return }
        let timestamp = now()
        record.lifeStatusRaw = PlantLifeStatus.active.rawValue
        record.lifeEventAt = nil
        record.lifeEventReason = nil
        record.giftRecipient = nil
        record.updatedAt = timestamp

        let hasOngoing = try sessionRecords(plantID: plantID).contains { $0.endedAt == nil }
        if !hasOngoing {
            context.insert(GrowthSessionRecord(
                plantID: plantID,
                stageKey: GrowthStageKey.leafRoot,
                startedAt: timestamp,
                note: "恢复档案后重新开始",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
        }
        insertJournal(
            plantID: plantID,
            kind: .restored,
            occurredAt: timestamp,
            title: "恢复档案",
            body: "已恢复为存活，并重新开始养叶养根。",
            sourceType: .lifeEvent,
            sourceID: plantID,
            uniqueKey: "restore:\(plantID.uuidString):\(timestamp.timeIntervalSince1970)"
        )
        try save()
    }

    func delete(plantID: UUID) throws {
        let record = try plantRecord(id: plantID)
        let photos = try photoRecords(plantID: plantID)
        for photo in photos {
            deletePhotoFile(photo)
            context.delete(photo)
        }
        for session in try sessionRecords(plantID: plantID) {
            context.delete(session)
        }
        for log in try careLogRecords(plantID: plantID) {
            context.delete(log)
        }
        for reminder in try reminderRecords(plantID: plantID) {
            context.delete(reminder)
        }
        for journal in try journalRecords(plantID: plantID) {
            context.delete(journal)
        }
        let ledger = try ledgerEntryRecords().filter { $0.plantID == plantID }
        for entry in ledger {
            entry.plantID = nil
            entry.updatedAt = now()
        }
        let imports = try context.fetch(FetchDescriptor<OrderImportRecordModel>())
        for record in imports where record.importedPlantID == plantID {
            record.importedPlantID = nil
        }
        context.delete(record)
        try save()
    }

    func addManualJournal(plantID: UUID, occurredAt: Date, text: String, photos: [ImagePayload]) throws {
        _ = try plantRecord(id: plantID)
        let timestamp = now()
        let journalID = UUID()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        insertJournal(
            plantID: plantID,
            kind: .manual,
            occurredAt: occurredAt,
            title: "手动日志",
            body: body.isEmpty ? "记录了照片" : body,
            sourceType: .manual,
            sourceID: journalID,
            uniqueKey: "manual:\(journalID.uuidString)",
            isManual: true
        )
        do {
            for payload in photos {
                _ = try insertPhoto(
                    plantID: plantID,
                    payload: payload,
                    source: .journal,
                    sourceID: journalID,
                    logPhoto: false
                )
            }
            try save()
        } catch {
            throw error
        }
    }

    // MARK: - Helpers

    func stageRecord(key: String) throws -> GrowthStageRecord? {
        let descriptor = FetchDescriptor<GrowthStageRecord>(predicate: #Predicate { $0.key == key })
        return try context.fetch(descriptor).first
    }

    private func purchaseLedgerDraft(
        base: LedgerDraft,
        fallbackPlatform: String?,
        fallbackStore: String?
    ) -> LedgerDraft {
        var draft = base
        if draft.trimmedTitle.isEmpty {
            draft.title = "采购"
        }
        if draft.platform.isEmpty { draft.platform = fallbackPlatform ?? "" }
        if draft.storeName.isEmpty { draft.storeName = fallbackStore ?? "" }
        return draft
    }

    @discardableResult
    func insertPurchaseLedger(
        draft: LedgerDraft,
        title: String,
        plantID: UUID?,
        toolID: UUID?,
        sourceType: LedgerSourceType,
        sourceID: UUID,
        timestamp: Date
    ) -> LedgerEntryRecord? {
        guard let amount = draft.amount, amount > 0 else { return nil }
        let record = LedgerEntryRecord(
            kind: .expense,
            title: title,
            category: draft.category,
            amount: amount,
            occurredAt: draft.occurredAt,
            platform: PlantValidator.normalized(draft.platform),
            storeName: PlantValidator.normalized(draft.storeName),
            plantID: plantID,
            toolID: toolID,
            note: PlantValidator.normalized(draft.note),
            sourceType: sourceType,
            sourceID: sourceID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)
        return record
    }

    private func syncAutoPurchaseLedger(plantID: UUID, amount: Decimal, timestamp: Date) {
        guard amount > 0 else { return }
        let entries = (try? ledgerEntryRecords()) ?? []
        for entry in entries where entry.sourceTypeRaw == LedgerSourceType.plant.rawValue && entry.sourceID == plantID {
            entry.amount = amount
            entry.updatedAt = timestamp
        }
    }

    private func markImportCompleted(id: UUID, plantID: UUID) throws {
        let descriptor = FetchDescriptor<OrderImportRecordModel>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.status = "completed"
        record.importedPlantID = plantID
        record.updatedAt = now()
    }
}
