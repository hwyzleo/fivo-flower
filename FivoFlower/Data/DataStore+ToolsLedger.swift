import Foundation
import SwiftData

extension FivoDataStore: ToolRepository {

    func tools() throws -> [ToolItem] {
        try context.fetch(FetchDescriptor<ToolItemRecord>())
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.domain)
    }

    func tool(id: UUID) throws -> ToolItem? {
        try? toolRecord(id: id).domain
    }

    func createTool(draft: ToolDraft, photo: ImagePayload?, ledgerDraft: LedgerDraft?) throws -> ToolItem {
        let errors = ToolValidator.validate(draft)
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        if draft.lowStockEnabled && draft.lowStockThreshold == nil {
            throw DataError.validation("开启低库存提醒时需要填写阈值")
        }
        let timestamp = now()
        var photoPath: String?
        if let photo {
            let saved = try imageStore.saveImage(data: photo.data)
            photoPath = saved.originalRelativePath
        }
        let record = ToolItemRecord(
            name: draft.trimmedName,
            category: draft.category,
            brand: PlantValidator.normalized(draft.brand),
            specification: PlantValidator.normalized(draft.specification),
            purchasedAt: draft.purchasedAt,
            purchasePrice: draft.purchasePrice,
            quantity: draft.quantity,
            location: PlantValidator.normalized(draft.location),
            photoRelativePath: photoPath,
            notes: PlantValidator.normalized(draft.notes),
            isConsumable: draft.isConsumable,
            stock: draft.stock ?? 0,
            stockUnit: draft.stockUnit.isEmpty ? "个" : draft.stockUnit,
            lowStockThreshold: draft.lowStockThreshold,
            lowStockEnabled: draft.lowStockEnabled,
            isDevice: draft.category.isDeviceCandidate && draft.isDevice,
            isPoweredOn: draft.category.isDeviceCandidate && draft.isDevice && draft.isPoweredOn,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)

        if draft.generateLedger, let price = draft.purchasePrice, price > 0 {
            var ledger = ledgerDraft ?? LedgerDraft()
            ledger.kind = .expense
            ledger.category = categoryForTool(draft.category)
            ledger.amountText = FivoMoney.plainString(price)
            ledger.occurredAt = draft.purchasedAt ?? timestamp
            ledger.title = ledger.trimmedTitle.isEmpty ? "工具采购：\(record.name)" : ledger.trimmedTitle
            insertPurchaseLedger(
                draft: ledger,
                title: ledger.title,
                plantID: nil,
                toolID: record.id,
                sourceType: .tool,
                sourceID: record.id,
                timestamp: timestamp
            )
        }
        do {
            try save()
        } catch {
            if let photoPath { try? imageStore.delete(relativePath: photoPath) }
            throw error
        }
        return record.domain
    }

    func updateTool(id: UUID, draft: ToolDraft) throws -> ToolItem {
        let errors = ToolValidator.validate(draft)
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        if draft.lowStockEnabled && draft.lowStockThreshold == nil {
            throw DataError.validation("开启低库存提醒时需要填写阈值")
        }
        let record = try toolRecord(id: id)
        record.name = draft.trimmedName
        record.categoryRaw = draft.category.rawValue
        record.brand = PlantValidator.normalized(draft.brand)
        record.specification = PlantValidator.normalized(draft.specification)
        record.purchasedAt = draft.purchasedAt
        record.purchasePrice = draft.purchasePrice
        record.quantity = draft.quantity
        record.location = PlantValidator.normalized(draft.location)
        record.notes = PlantValidator.normalized(draft.notes)
        record.isConsumable = draft.isConsumable
        record.stockUnit = draft.stockUnit.isEmpty ? record.stockUnit : draft.stockUnit
        record.lowStockEnabled = draft.lowStockEnabled
        record.lowStockThreshold = draft.lowStockThreshold
        record.isDevice = draft.category.isDeviceCandidate && draft.isDevice
        if !record.isDevice { record.isPoweredOn = false }
        record.updatedAt = now()
        try save()
        return record.domain
    }

    func replacePhoto(toolID: UUID, payload: ImagePayload) throws {
        let record = try toolRecord(id: toolID)
        let saved = try imageStore.saveImage(data: payload.data)
        if let old = record.photoRelativePath {
            try? imageStore.delete(relativePath: old)
        }
        record.photoRelativePath = saved.originalRelativePath
        record.updatedAt = now()
        try save()
    }

    func setPowerState(id: UUID, isOn: Bool) throws {
        let record = try toolRecord(id: id)
        guard record.isDevice else {
            throw DataError.validation("该工具不是可切换状态的设备")
        }
        record.isPoweredOn = isOn
        record.updatedAt = now()
        try save()
    }

    func adjustStock(toolID: UUID, draft: StockDraft, at date: Date) throws {
        let record = try toolRecord(id: toolID)
        guard record.isConsumable else {
            throw DataError.validation("只有消耗品支持库存调整")
        }
        guard let amount = draft.amount, amount > 0 || draft.mode == .calibrate else {
            throw DataError.validation("请填写有效的调整数量")
        }
        let previousStock = record.stock
        let resulting = try StockCalculator.resultingStock(
            current: previousStock,
            mode: draft.mode,
            amount: amount
        )
        let timestamp = now()
        record.stock = resulting
        record.updatedAt = timestamp
        context.insert(StockAdjustmentRecord(
            toolID: toolID,
            mode: draft.mode,
            delta: resulting - previousStock,
            resultingStock: resulting,
            occurredAt: date,
            note: PlantValidator.normalized(draft.note),
            createdAt: timestamp
        ))
        try save()
    }

    func stockAdjustments(toolID: UUID) throws -> [StockAdjustment] {
        let descriptor = FetchDescriptor<StockAdjustmentRecord>(predicate: #Predicate { $0.toolID == toolID })
        return try context.fetch(descriptor)
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func toolPhotos(toolID: UUID) throws -> [ToolPhoto] {
        let descriptor = FetchDescriptor<ToolPhotoRecord>(predicate: #Predicate { $0.toolID == toolID })
        return try context.fetch(descriptor)
            .sorted { $0.capturedAt > $1.capturedAt }
            .map(\.domain)
    }

    func addToolPhotos(toolID: UUID, payloads: [ImagePayload], caption: String?) throws -> [ToolPhoto] {
        _ = try toolRecord(id: toolID)
        let normalizedCaption = caption.flatMap { PlantValidator.normalized($0) }
        var created: [ToolPhotoRecord] = []
        do {
            for payload in payloads {
                let saved = try imageStore.saveImage(data: payload.data)
                let record = ToolPhotoRecord(
                    toolID: toolID,
                    originalRelativePath: saved.originalRelativePath,
                    thumbnailRelativePath: saved.thumbnailRelativePath,
                    capturedAt: payload.capturedAt,
                    caption: normalizedCaption,
                    createdAt: now()
                )
                context.insert(record)
                created.append(record)
            }
            try save()
            return created.map(\.domain)
        } catch {
            for photo in created {
                deleteToolPhotoFiles(photo)
                context.delete(photo)
            }
            throw error
        }
    }

    func deleteToolPhoto(id: UUID) throws {
        let descriptor = FetchDescriptor<ToolPhotoRecord>(predicate: #Predicate { $0.id == id })
        guard let photo = try context.fetch(descriptor).first else { return }
        deleteToolPhotoFiles(photo)
        context.delete(photo)
        try save()
    }

    func deleteTool(id: UUID) throws {
        let record = try toolRecord(id: id)
        if let photoPath = record.photoRelativePath {
            try? imageStore.delete(relativePath: photoPath)
        }
        let toolPhotos = try context.fetch(FetchDescriptor<ToolPhotoRecord>())
        for photo in toolPhotos where photo.toolID == id {
            deleteToolPhotoFiles(photo)
            context.delete(photo)
        }
        let adjustments = try context.fetch(FetchDescriptor<StockAdjustmentRecord>())
        for adjustment in adjustments where adjustment.toolID == id {
            context.delete(adjustment)
        }
        for entry in try ledgerEntryRecords() where entry.toolID == id {
            entry.toolID = nil
            entry.updatedAt = now()
        }
        context.delete(record)
        try save()
    }

    func toolRecord(id: UUID) throws -> ToolItemRecord {
        let descriptor = FetchDescriptor<ToolItemRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw DataError.notFound("工具资材")
        }
        return record
    }

    private func deleteToolPhotoFiles(_ record: ToolPhotoRecord) {
        try? imageStore.delete(relativePath: record.originalRelativePath)
        try? imageStore.delete(relativePath: record.thumbnailRelativePath)
    }

    private func categoryForTool(_ category: ToolCategory) -> LedgerCategory {
        switch category {
        case .medium: return .medium
        case .growLight, .ventilation: return .equipment
        default: return .toolPurchase
        }
    }
}

extension FivoDataStore: LedgerRepository {

    func entries() throws -> [LedgerEntry] {
        try ledgerEntryRecords()
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func entry(id: UUID) throws -> LedgerEntry? {
        let descriptor = FetchDescriptor<LedgerEntryRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first?.domain
    }

    func createEntry(_ draft: LedgerDraft) throws -> LedgerEntry {
        let errors = LedgerValidator.validate(draft, now: now())
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        guard let amount = draft.amount else {
            throw DataError.validation("请填写有效金额")
        }
        let timestamp = now()
        let record = LedgerEntryRecord(
            kind: draft.kind,
            title: draft.trimmedTitle,
            category: draft.category,
            amount: FivoMoney.round2(amount),
            occurredAt: draft.occurredAt,
            platform: PlantValidator.normalized(draft.platform),
            storeName: PlantValidator.normalized(draft.storeName),
            plantID: draft.plantID,
            toolID: draft.toolID,
            note: PlantValidator.normalized(draft.note),
            sourceType: .manual,
            sourceID: nil,
            relatedEntryID: draft.relatedEntryID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)
        try save()
        return record.domain
    }

    func updateEntry(id: UUID, draft: LedgerDraft) throws -> LedgerEntry {
        let errors = LedgerValidator.validate(draft, now: now())
        if let first = errors.first {
            throw DataError.validation(first.message)
        }
        guard let amount = draft.amount else {
            throw DataError.validation("请填写有效金额")
        }
        let descriptor = FetchDescriptor<LedgerEntryRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else {
            throw DataError.notFound("账目")
        }
        record.kindRaw = draft.kind.rawValue
        record.title = draft.trimmedTitle
        record.categoryRaw = draft.category.rawValue
        record.amount = FivoMoney.round2(amount)
        record.occurredAt = draft.occurredAt
        record.platform = PlantValidator.normalized(draft.platform)
        record.storeName = PlantValidator.normalized(draft.storeName)
        record.plantID = draft.plantID
        record.toolID = draft.toolID
        record.note = PlantValidator.normalized(draft.note)
        record.relatedEntryID = draft.kind == .refund ? draft.relatedEntryID : nil
        record.updatedAt = now()
        try save()
        return record.domain
    }

    func deleteEntry(id: UUID) throws {
        let descriptor = FetchDescriptor<LedgerEntryRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        let timestamp = now()
        for refund in try ledgerEntryRecords() where refund.relatedEntryID == id {
            refund.relatedEntryID = nil
            refund.updatedAt = timestamp
        }
        context.delete(record)
        try save()
    }

    func entries(plantID: UUID?) throws -> [LedgerEntry] {
        guard let plantID else { return try entries() }
        return try ledgerEntryRecords()
            .filter { $0.plantID == plantID }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func entries(toolID: UUID?) throws -> [LedgerEntry] {
        guard let toolID else { return try entries() }
        return try ledgerEntryRecords()
            .filter { $0.toolID == toolID }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func ledgerEntryRecords() throws -> [LedgerEntryRecord] {
        try context.fetch(FetchDescriptor<LedgerEntryRecord>())
    }
}

// MARK: - Import

private struct StoredOrderDraft: Codable {
    var plantName: String
    var specification: String
    var acquiredAt: Date?
    var amountText: String
    var platform: String
    var storeName: String
    var orderNumber: String
    var sourceURL: String
    var rawOCRText: String
    var createLedgerEntry: Bool
    var lowConfidenceFields: [String]
    var attachmentIDs: [UUID]

    init(draft: OrderDraft) {
        plantName = draft.plantName
        specification = draft.specification
        acquiredAt = draft.acquiredAt
        amountText = draft.amountText
        platform = draft.platform
        storeName = draft.storeName
        orderNumber = draft.orderNumber
        sourceURL = draft.sourceURL
        rawOCRText = draft.rawOCRText
        createLedgerEntry = draft.createLedgerEntry
        lowConfidenceFields = draft.lowConfidenceFields.map(\.rawValue)
        attachmentIDs = draft.attachmentIDs
    }
}

extension FivoDataStore: ImportRepository {

    func createImportRecord(rawOCRText: String, draft: OrderDraft) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(StoredOrderDraft(draft: draft))
        let ids = (try? JSONEncoder().encode(draft.attachmentIDs)) ?? Data("[]".utf8)
        let timestamp = now()
        let record = OrderImportRecordModel(
            attachmentIDsJSON: String(data: ids, encoding: .utf8) ?? "[]",
            rawOCRText: rawOCRText,
            recognizedDraftJSON: String(data: payload, encoding: .utf8) ?? "{}",
            status: "draft",
            orderNumber: PlantValidator.normalized(draft.orderNumber),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(record)
        try save()
        return record.id
    }

    func updateImportRecord(id: UUID, status: String, failureMessage: String?, plantID: UUID?) throws {
        let descriptor = FetchDescriptor<OrderImportRecordModel>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.status = status
        record.failureMessage = failureMessage
        record.importedPlantID = plantID
        record.updatedAt = now()
        try save()
    }

    func importRecord(id: UUID) throws -> OrderImportRecord? {
        let descriptor = FetchDescriptor<OrderImportRecordModel>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first?.domain
    }

    func duplicateCandidates(orderNumber: String, attachmentIDs: [UUID], rawOCRText: String) throws -> [OrderImportRecord] {
        let all = try context.fetch(FetchDescriptor<OrderImportRecordModel>()).map(\.domain)
        let normalizedNumber = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentSet = Set(attachmentIDs)
        let normalizedText = rawOCRText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return all.filter { record in
            guard record.status == "completed" else { return false }
            if !normalizedNumber.isEmpty, record.orderNumber == normalizedNumber {
                return true
            }
            if !attachmentSet.isDisjoint(with: Set(record.attachmentIDs)) {
                return true
            }
            let existingText = record.rawOCRText
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
            return !normalizedText.isEmpty && existingText == normalizedText
        }
    }

    func clearUnfinishedImports() throws {
        let all = try context.fetch(FetchDescriptor<OrderImportRecordModel>())
        let unfinished = all.filter { $0.status != "completed" }
        for record in unfinished {
            context.delete(record)
        }
        let attachments = try context.fetch(FetchDescriptor<OrderAttachmentRecord>())
        for attachment in attachments {
            try? imageStore.delete(relativePath: attachment.originalRelativePath)
            try? imageStore.delete(relativePath: attachment.thumbnailRelativePath)
            context.delete(attachment)
        }
        try save()
    }

    // MARK: - Temporary order attachments

    @discardableResult
    func saveOrderAttachment(payload: ImagePayload) throws -> OrderAttachmentRecord {
        let saved = try imageStore.saveImage(data: payload.data)
        let record = OrderAttachmentRecord(
            originalRelativePath: saved.originalRelativePath,
            thumbnailRelativePath: saved.thumbnailRelativePath,
            createdAt: now()
        )
        context.insert(record)
        try save()
        return record
    }

    func orderAttachment(id: UUID) throws -> OrderAttachmentRecord? {
        let descriptor = FetchDescriptor<OrderAttachmentRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func orderAttachmentPayloads(ids: [UUID]) throws -> [ImagePayload] {
        try ids.compactMap { id in
            guard let record = try orderAttachment(id: id) else { return nil }
            let url = imageStore.absoluteURL(for: record.originalRelativePath)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImagePayload(data: data, capturedAt: record.createdAt)
        }
    }

    func cleanupOrderAttachments(ids: [UUID]) {
        for id in ids {
            guard let record = try? orderAttachment(id: id) else { continue }
            try? imageStore.delete(relativePath: record.originalRelativePath)
            try? imageStore.delete(relativePath: record.thumbnailRelativePath)
            context.delete(record)
        }
        try? save()
    }

    func allSessions() throws -> [GrowthSession] {
        try allRecords(GrowthSessionRecord.self).map(\.domain)
    }

    func allImportRecords() throws -> [OrderImportRecord] {
        try context.fetch(FetchDescriptor<OrderImportRecordModel>())
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.domain)
    }
}
