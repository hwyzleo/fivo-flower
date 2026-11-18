import Foundation

// MARK: - Manifest

struct BackupManifest: Codable, Equatable {
    var formatVersion: Int
    var appVersion: String
    var createdAt: Date
    var counts: [String: Int]
    var mediaFiles: [String]
}

struct BackupData: Codable {
    var plants: [PlantDTO]
    var stages: [GrowthStageDTO]
    var sessions: [GrowthSessionDTO]
    var photos: [PhotoDTO]
    var journals: [JournalDTO]
    var actionTypes: [CareActionTypeDTO]
    var careLogs: [CareLogDTO]
    var reminders: [ReminderDTO]
    var tools: [ToolDTO]
    var toolPhotos: [ToolPhotoDTO]?
    var stockAdjustments: [StockAdjustmentDTO]
    var ledgerEntries: [LedgerDTO]
    var importRecords: [ImportRecordDTO]
}

// MARK: - DTOs

struct PlantDTO: Codable {
    var id: UUID
    var name: String
    var alias: String?
    var plantCode: String?
    var specification: String?
    var acquiredAt: Date?
    var purchasePrice: String?
    var currency: String
    var platform: String?
    var storeName: String?
    var sourceURL: String?
    var medium: String?
    var location: String?
    var notes: String?
    var lifeStatus: String
    var lifeEventAt: Date?
    var lifeEventReason: String?
    var giftRecipient: String?
    var coverPhotoID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ plant: Plant) {
        id = plant.id
        name = plant.name
        alias = plant.alias
        plantCode = plant.plantCode
        specification = plant.specification
        acquiredAt = plant.acquiredAt
        purchasePrice = plant.purchasePrice.map(FivoMoney.plainString)
        currency = plant.currency
        platform = plant.platform
        storeName = plant.storeName
        sourceURL = plant.sourceURL
        medium = plant.medium
        location = plant.location
        notes = plant.notes
        lifeStatus = plant.lifeStatus.rawValue
        lifeEventAt = plant.lifeEventAt
        lifeEventReason = plant.lifeEventReason
        giftRecipient = plant.giftRecipient
        coverPhotoID = plant.coverPhotoID
        createdAt = plant.createdAt
        updatedAt = plant.updatedAt
    }

    func domain() throws -> Plant {
        Plant(
            id: id,
            name: name,
            alias: alias,
            plantCode: plantCode,
            specification: specification,
            acquiredAt: acquiredAt,
            purchasePrice: purchasePrice.flatMap(FivoMoney.parse),
            currency: currency,
            platform: platform,
            storeName: storeName,
            sourceURL: sourceURL,
            medium: medium,
            location: location,
            notes: notes,
            lifeStatus: PlantLifeStatus(rawValue: lifeStatus) ?? .active,
            lifeEventAt: lifeEventAt,
            lifeEventReason: lifeEventReason,
            giftRecipient: giftRecipient,
            coverPhotoID: coverPhotoID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct GrowthStageDTO: Codable {
    var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int
    var colorToken: String

    init(_ stage: GrowthStage) {
        key = stage.key
        name = stage.name
        isBuiltIn = stage.isBuiltIn
        isEnabled = stage.isEnabled
        sortOrder = stage.sortOrder
        colorToken = stage.colorToken
    }

    func domain() -> GrowthStage {
        GrowthStage(
            key: key,
            name: name,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabled,
            sortOrder: sortOrder,
            colorToken: colorToken
        )
    }
}

struct GrowthSessionDTO: Codable {
    var id: UUID
    var plantID: UUID
    var stageKey: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(_ session: GrowthSession) {
        id = session.id
        plantID = session.plantID
        stageKey = session.stageKey
        startedAt = session.startedAt
        endedAt = session.endedAt
        note = session.note
        createdAt = session.createdAt
        updatedAt = session.updatedAt
    }

    func domain() -> GrowthSession {
        GrowthSession(
            id: id,
            plantID: plantID,
            stageKey: stageKey,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct PhotoDTO: Codable {
    var id: UUID
    var plantID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var sourceType: String
    var sourceID: UUID?
    var coverCropData: Data?
    var createdAt: Date

    init(_ photo: PlantPhoto) {
        id = photo.id
        plantID = photo.plantID
        originalRelativePath = photo.originalRelativePath
        thumbnailRelativePath = photo.thumbnailRelativePath
        capturedAt = photo.capturedAt
        caption = photo.caption
        sourceType = photo.sourceType.rawValue
        sourceID = photo.sourceID
        coverCropData = photo.coverCropData
        createdAt = photo.createdAt
    }

    func domain() -> PlantPhoto {
        PlantPhoto(
            id: id,
            plantID: plantID,
            originalRelativePath: originalRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            capturedAt: capturedAt,
            caption: caption,
            sourceType: PhotoSourceType(rawValue: sourceType) ?? .plant,
            sourceID: sourceID,
            coverCropData: coverCropData,
            createdAt: createdAt
        )
    }
}

struct JournalDTO: Codable {
    var id: UUID
    var plantID: UUID
    var kind: String
    var occurredAt: Date
    var title: String
    var body: String
    var sourceType: String?
    var sourceID: UUID?
    var isManual: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ entry: JournalEntry) {
        id = entry.id
        plantID = entry.plantID
        kind = entry.kind.rawValue
        occurredAt = entry.occurredAt
        title = entry.title
        body = entry.body
        sourceType = entry.sourceType?.rawValue
        sourceID = entry.sourceID
        isManual = entry.isManual
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func domain() -> JournalEntry {
        JournalEntry(
            id: id,
            plantID: plantID,
            kind: JournalKind(rawValue: kind) ?? .manual,
            occurredAt: occurredAt,
            title: title,
            body: body,
            sourceType: sourceType.flatMap(JournalSourceType.init(rawValue:)),
            sourceID: sourceID,
            isManual: isManual,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct CareActionTypeDTO: Codable {
    var id: UUID
    var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int

    init(_ action: CareActionType) {
        id = action.id
        key = action.key
        name = action.name
        isBuiltIn = action.isBuiltIn
        isEnabled = action.isEnabled
        sortOrder = action.sortOrder
    }

    func domain() -> CareActionType {
        CareActionType(
            id: id,
            key: key,
            name: name,
            isBuiltIn: isBuiltIn,
            isEnabled: isEnabled,
            sortOrder: sortOrder
        )
    }
}

struct CareLogDTO: Codable {
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

    init(_ log: CareLog) {
        id = log.id
        plantID = log.plantID
        actionTypeID = log.actionTypeID
        actionNameSnapshot = log.actionNameSnapshot
        occurredAt = log.occurredAt
        note = log.note
        dosage = log.dosage
        unit = log.unit
        batchID = log.batchID
        createdAt = log.createdAt
        updatedAt = log.updatedAt
    }

    func domain() -> CareLog {
        CareLog(
            id: id,
            plantID: plantID,
            actionTypeID: actionTypeID,
            actionNameSnapshot: actionNameSnapshot,
            occurredAt: occurredAt,
            note: note,
            dosage: dosage,
            unit: unit,
            batchID: batchID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ReminderDTO: Codable {
    var id: UUID
    var plantID: UUID
    var actionTypeID: UUID?
    var actionNameSnapshot: String?
    var title: String
    var dueAt: Date
    var recurrence: String
    var status: String
    var completedAt: Date?
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ reminder: CareReminder) {
        id = reminder.id
        plantID = reminder.plantID
        actionTypeID = reminder.actionTypeID
        actionNameSnapshot = reminder.actionNameSnapshot
        title = reminder.title
        dueAt = reminder.dueAt
        recurrence = reminder.recurrence.rawValue
        status = reminder.status.rawValue
        completedAt = reminder.completedAt
        groupID = reminder.groupID
        createdAt = reminder.createdAt
        updatedAt = reminder.updatedAt
    }

    func domain() -> CareReminder? {
        guard let recurrence = ReminderRecurrence(rawValue: recurrence) else { return nil }
        return CareReminder(
            id: id,
            plantID: plantID,
            actionTypeID: actionTypeID,
            actionNameSnapshot: actionNameSnapshot,
            title: title,
            dueAt: dueAt,
            recurrence: recurrence,
            status: ReminderStatus(rawValue: status) ?? .pending,
            completedAt: completedAt,
            notificationID: nil,
            groupID: groupID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ToolDTO: Codable {
    var id: UUID
    var name: String
    var category: String
    var brand: String?
    var specification: String?
    var purchasedAt: Date?
    var purchasePrice: String?
    var quantity: Int
    var location: String?
    var photoRelativePath: String?
    var notes: String?
    var isConsumable: Bool
    var stock: String
    var stockUnit: String
    var lowStockThreshold: String?
    var lowStockEnabled: Bool
    var isDevice: Bool
    var isPoweredOn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ tool: ToolItem) {
        id = tool.id
        name = tool.name
        category = tool.category.rawValue
        brand = tool.brand
        specification = tool.specification
        purchasedAt = tool.purchasedAt
        purchasePrice = tool.purchasePrice.map(FivoMoney.plainString)
        quantity = tool.quantity
        location = tool.location
        photoRelativePath = tool.photoRelativePath
        notes = tool.notes
        isConsumable = tool.isConsumable
        stock = FivoMoney.plainString(tool.stock)
        stockUnit = tool.stockUnit
        lowStockThreshold = tool.lowStockThreshold.map(FivoMoney.plainString)
        lowStockEnabled = tool.lowStockEnabled
        isDevice = tool.isDevice
        isPoweredOn = tool.isPoweredOn
        createdAt = tool.createdAt
        updatedAt = tool.updatedAt
    }

    func domain() -> ToolItem {
        ToolItem(
            id: id,
            name: name,
            category: ToolCategory(rawValue: category) ?? .other,
            brand: brand,
            specification: specification,
            purchasedAt: purchasedAt,
            purchasePrice: purchasePrice.flatMap(FivoMoney.parse),
            quantity: quantity,
            location: location,
            photoRelativePath: photoRelativePath,
            notes: notes,
            isConsumable: isConsumable,
            stock: FivoMoney.parse(stock) ?? 0,
            stockUnit: stockUnit,
            lowStockThreshold: lowStockThreshold.flatMap(FivoMoney.parse),
            lowStockEnabled: lowStockEnabled,
            isDevice: isDevice,
            isPoweredOn: isPoweredOn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ToolPhotoDTO: Codable {
    var id: UUID
    var toolID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var createdAt: Date

    init(_ photo: ToolPhoto) {
        id = photo.id
        toolID = photo.toolID
        originalRelativePath = photo.originalRelativePath
        thumbnailRelativePath = photo.thumbnailRelativePath
        capturedAt = photo.capturedAt
        caption = photo.caption
        createdAt = photo.createdAt
    }

    func domain() -> ToolPhoto {
        ToolPhoto(
            id: id,
            toolID: toolID,
            originalRelativePath: originalRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            capturedAt: capturedAt,
            caption: caption,
            createdAt: createdAt
        )
    }
}

struct StockAdjustmentDTO: Codable {
    var id: UUID
    var toolID: UUID
    var mode: String
    var delta: String?
    var resultingStock: String
    var occurredAt: Date
    var note: String?
    var createdAt: Date

    init(_ adjustment: StockAdjustment) {
        id = adjustment.id
        toolID = adjustment.toolID
        mode = adjustment.mode.rawValue
        delta = adjustment.delta.map(FivoMoney.plainString)
        resultingStock = FivoMoney.plainString(adjustment.resultingStock)
        occurredAt = adjustment.occurredAt
        note = adjustment.note
        createdAt = adjustment.createdAt
    }

    func domain() -> StockAdjustment {
        StockAdjustment(
            id: id,
            toolID: toolID,
            mode: StockAdjustmentMode(rawValue: mode) ?? .calibrate,
            delta: delta.flatMap(FivoMoney.parse),
            resultingStock: FivoMoney.parse(resultingStock) ?? 0,
            occurredAt: occurredAt,
            note: note,
            createdAt: createdAt
        )
    }
}

struct LedgerDTO: Codable {
    var id: UUID
    var kind: String
    var title: String
    var category: String
    var amount: String
    var currency: String
    var occurredAt: Date
    var platform: String?
    var storeName: String?
    var plantID: UUID?
    var toolID: UUID?
    var note: String?
    var sourceType: String?
    var sourceID: UUID?
    var relatedEntryID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ entry: LedgerEntry) {
        id = entry.id
        kind = entry.kind.rawValue
        title = entry.title
        category = entry.category.rawValue
        amount = FivoMoney.plainString(entry.amount)
        currency = entry.currency
        occurredAt = entry.occurredAt
        platform = entry.platform
        storeName = entry.storeName
        plantID = entry.plantID
        toolID = entry.toolID
        note = entry.note
        sourceType = entry.sourceType?.rawValue
        sourceID = entry.sourceID
        relatedEntryID = entry.relatedEntryID
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    func domain() -> LedgerEntry {
        LedgerEntry(
            id: id,
            kind: LedgerKind(rawValue: kind) ?? .expense,
            title: title,
            category: LedgerCategory(rawValue: category) ?? .otherExpense,
            amount: FivoMoney.parse(amount) ?? 0,
            currency: currency,
            occurredAt: occurredAt,
            platform: platform,
            storeName: storeName,
            plantID: plantID,
            toolID: toolID,
            note: note,
            sourceType: sourceType.flatMap(LedgerSourceType.init(rawValue:)),
            sourceID: sourceID,
            relatedEntryID: relatedEntryID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct ImportRecordDTO: Codable {
    var id: UUID
    var attachmentIDs: [UUID]
    var rawOCRText: String
    var recognizedDraftJSON: String
    var status: String
    var orderNumber: String?
    var failureMessage: String?
    var importedPlantID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ record: OrderImportRecord) {
        id = record.id
        attachmentIDs = record.attachmentIDs
        rawOCRText = record.rawOCRText
        recognizedDraftJSON = record.recognizedDraftJSON
        status = record.status
        orderNumber = record.orderNumber
        failureMessage = record.failureMessage
        importedPlantID = record.importedPlantID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func domain() -> OrderImportRecord {
        OrderImportRecord(
            id: id,
            attachmentIDs: attachmentIDs,
            rawOCRText: rawOCRText,
            recognizedDraftJSON: recognizedDraftJSON,
            status: status,
            orderNumber: orderNumber,
            failureMessage: failureMessage,
            importedPlantID: importedPlantID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Mapping

extension BackupData {
    init(snapshot: BackupDomainSnapshot) {
        plants = snapshot.plants.map(PlantDTO.init)
        stages = snapshot.stages.map(GrowthStageDTO.init)
        sessions = snapshot.sessions.map(GrowthSessionDTO.init)
        photos = snapshot.photos.map(PhotoDTO.init)
        journals = snapshot.journals.map(JournalDTO.init)
        actionTypes = snapshot.actionTypes.map(CareActionTypeDTO.init)
        careLogs = snapshot.careLogs.map(CareLogDTO.init)
        reminders = snapshot.reminders.map(ReminderDTO.init)
        tools = snapshot.tools.map(ToolDTO.init)
        toolPhotos = snapshot.toolPhotos.map(ToolPhotoDTO.init)
        stockAdjustments = snapshot.stockAdjustments.map(StockAdjustmentDTO.init)
        ledgerEntries = snapshot.ledgerEntries.map(LedgerDTO.init)
        importRecords = snapshot.importRecords.map(ImportRecordDTO.init)
    }

    func snapshot() throws -> BackupDomainSnapshot {
        BackupDomainSnapshot(
            plants: try plants.map { try $0.domain() },
            stages: stages.map { $0.domain() },
            sessions: sessions.map { $0.domain() },
            photos: photos.map { $0.domain() },
            journals: journals.map { $0.domain() },
            actionTypes: actionTypes.map { $0.domain() },
            careLogs: careLogs.map { $0.domain() },
            reminders: reminders.compactMap { $0.domain() },
            tools: tools.map { $0.domain() },
            toolPhotos: (toolPhotos ?? []).map { $0.domain() },
            stockAdjustments: stockAdjustments.map { $0.domain() },
            ledgerEntries: ledgerEntries.map { $0.domain() },
            importRecords: importRecords.map { $0.domain() }
        )
    }

    var mediaReferences: [String] {
        var paths = Set<String>()
        for photo in photos {
            paths.insert(photo.originalRelativePath)
            paths.insert(photo.thumbnailRelativePath)
        }
        for tool in tools {
            if let path = tool.photoRelativePath { paths.insert(path) }
        }
        for photo in toolPhotos ?? [] {
            paths.insert(photo.originalRelativePath)
            paths.insert(photo.thumbnailRelativePath)
        }
        return paths.sorted()
    }
}
