import Foundation
import SwiftData

// MARK: - Plant

@Model
final class PlantRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var alias: String?
    var plantCode: String?
    var specification: String?
    var acquiredAt: Date?
    var purchasePrice: Decimal?
    var currency: String
    var platform: String?
    var storeName: String?
    var sourceURL: String?
    var medium: String?
    var location: String?
    var notes: String?
    var lifeStatusRaw: String
    var lifeEventAt: Date?
    var lifeEventReason: String?
    var giftRecipient: String?
    var coverPhotoID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        alias: String? = nil,
        plantCode: String? = nil,
        specification: String? = nil,
        acquiredAt: Date? = nil,
        purchasePrice: Decimal? = nil,
        currency: String = "CNY",
        platform: String? = nil,
        storeName: String? = nil,
        sourceURL: String? = nil,
        medium: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        lifeStatus: PlantLifeStatus = .active,
        lifeEventAt: Date? = nil,
        lifeEventReason: String? = nil,
        giftRecipient: String? = nil,
        coverPhotoID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.plantCode = plantCode
        self.specification = specification
        self.acquiredAt = acquiredAt
        self.purchasePrice = purchasePrice
        self.currency = currency
        self.platform = platform
        self.storeName = storeName
        self.sourceURL = sourceURL
        self.medium = medium
        self.location = location
        self.notes = notes
        self.lifeStatusRaw = lifeStatus.rawValue
        self.lifeEventAt = lifeEventAt
        self.lifeEventReason = lifeEventReason
        self.giftRecipient = giftRecipient
        self.coverPhotoID = coverPhotoID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: Plant {
        Plant(
            id: id,
            name: name,
            alias: alias,
            plantCode: plantCode,
            specification: specification,
            acquiredAt: acquiredAt,
            purchasePrice: purchasePrice,
            currency: currency,
            platform: platform,
            storeName: storeName,
            sourceURL: sourceURL,
            medium: medium,
            location: location,
            notes: notes,
            lifeStatus: PlantLifeStatus(rawValue: lifeStatusRaw) ?? .active,
            lifeEventAt: lifeEventAt,
            lifeEventReason: lifeEventReason,
            giftRecipient: giftRecipient,
            coverPhotoID: coverPhotoID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Growth

@Model
final class GrowthStageRecord {
    @Attribute(.unique) var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int
    var colorToken: String

    init(key: String, name: String, isBuiltIn: Bool, isEnabled: Bool, sortOrder: Int, colorToken: String) {
        self.key = key
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.colorToken = colorToken
    }

    var domain: GrowthStage {
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

@Model
final class GrowthSessionRecord {
    @Attribute(.unique) var id: UUID
    var plantID: UUID
    var stageKey: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        plantID: UUID,
        stageKey: String,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.stageKey = stageKey
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: GrowthSession {
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

// MARK: - Photos

@Model
final class PlantPhotoRecord {
    @Attribute(.unique) var id: UUID
    var plantID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var sourceTypeRaw: String
    var sourceID: UUID?
    var coverCropData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        plantID: UUID,
        originalRelativePath: String,
        thumbnailRelativePath: String,
        capturedAt: Date,
        caption: String? = nil,
        sourceType: PhotoSourceType,
        sourceID: UUID? = nil,
        coverCropData: Data? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.originalRelativePath = originalRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.capturedAt = capturedAt
        self.caption = caption
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceID = sourceID
        self.coverCropData = coverCropData
        self.createdAt = createdAt
    }

    var domain: PlantPhoto {
        PlantPhoto(
            id: id,
            plantID: plantID,
            originalRelativePath: originalRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            capturedAt: capturedAt,
            caption: caption,
            sourceType: PhotoSourceType(rawValue: sourceTypeRaw) ?? .plant,
            sourceID: sourceID,
            coverCropData: coverCropData,
            createdAt: createdAt
        )
    }
}

// MARK: - Order attachments (temporary import files)

@Model
final class OrderAttachmentRecord {
    @Attribute(.unique) var id: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var createdAt: Date

    init(id: UUID = UUID(), originalRelativePath: String, thumbnailRelativePath: String, createdAt: Date) {
        self.id = id
        self.originalRelativePath = originalRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.createdAt = createdAt
    }
}

// MARK: - Journal

@Model
final class JournalEntryRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var uniqueKey: String
    var plantID: UUID
    var kindRaw: String
    var occurredAt: Date
    var title: String
    var body: String
    var sourceTypeRaw: String?
    var sourceID: UUID?
    var isManual: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        uniqueKey: String,
        plantID: UUID,
        kind: JournalKind,
        occurredAt: Date,
        title: String,
        body: String,
        sourceType: JournalSourceType?,
        sourceID: UUID?,
        isManual: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.uniqueKey = uniqueKey
        self.plantID = plantID
        self.kindRaw = kind.rawValue
        self.occurredAt = occurredAt
        self.title = title
        self.body = body
        self.sourceTypeRaw = sourceType?.rawValue
        self.sourceID = sourceID
        self.isManual = isManual
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: JournalEntry {
        JournalEntry(
            id: id,
            plantID: plantID,
            kind: JournalKind(rawValue: kindRaw) ?? .manual,
            occurredAt: occurredAt,
            title: title,
            body: body,
            sourceType: sourceTypeRaw.flatMap(JournalSourceType.init(rawValue:)),
            sourceID: sourceID,
            isManual: isManual,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Care

@Model
final class CareActionTypeRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int

    init(id: UUID = UUID(), key: String, name: String, isBuiltIn: Bool, isEnabled: Bool, sortOrder: Int) {
        self.id = id
        self.key = key
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    var domain: CareActionType {
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

@Model
final class CareLogRecord {
    @Attribute(.unique) var id: UUID
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

    init(
        id: UUID = UUID(),
        plantID: UUID,
        actionTypeID: UUID?,
        actionNameSnapshot: String,
        occurredAt: Date,
        note: String? = nil,
        dosage: String? = nil,
        unit: String? = nil,
        batchID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.actionTypeID = actionTypeID
        self.actionNameSnapshot = actionNameSnapshot
        self.occurredAt = occurredAt
        self.note = note
        self.dosage = dosage
        self.unit = unit
        self.batchID = batchID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: CareLog {
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

@Model
final class CareReminderRecord {
    @Attribute(.unique) var id: UUID
    var plantID: UUID
    var actionTypeID: UUID?
    var actionNameSnapshot: String?
    var title: String
    var dueAt: Date
    var recurrenceRaw: String
    var statusRaw: String
    var completedAt: Date?
    var notificationID: String?
    var groupID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        plantID: UUID,
        actionTypeID: UUID?,
        actionNameSnapshot: String?,
        title: String,
        dueAt: Date,
        recurrence: ReminderRecurrence,
        status: ReminderStatus,
        completedAt: Date? = nil,
        notificationID: String? = nil,
        groupID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.plantID = plantID
        self.actionTypeID = actionTypeID
        self.actionNameSnapshot = actionNameSnapshot
        self.title = title
        self.dueAt = dueAt
        self.recurrenceRaw = recurrence.rawValue
        self.statusRaw = status.rawValue
        self.completedAt = completedAt
        self.notificationID = notificationID
        self.groupID = groupID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: CareReminder {
        CareReminder(
            id: id,
            plantID: plantID,
            actionTypeID: actionTypeID,
            actionNameSnapshot: actionNameSnapshot,
            title: title,
            dueAt: dueAt,
            recurrence: ReminderRecurrence(rawValue: recurrenceRaw) ?? .everyNDays(1),
            status: ReminderStatus(rawValue: statusRaw) ?? .pending,
            completedAt: completedAt,
            notificationID: notificationID,
            groupID: groupID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Tools

@Model
final class ToolItemRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRaw: String
    var brand: String?
    var specification: String?
    var purchasedAt: Date?
    var purchasePrice: Decimal?
    var quantity: Int
    var location: String?
    var photoRelativePath: String?
    var notes: String?
    var isConsumable: Bool
    var stock: Decimal
    var stockUnit: String
    var lowStockThreshold: Decimal?
    var lowStockEnabled: Bool
    var isDevice: Bool
    var isPoweredOn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: ToolCategory,
        brand: String? = nil,
        specification: String? = nil,
        purchasedAt: Date? = nil,
        purchasePrice: Decimal? = nil,
        quantity: Int = 1,
        location: String? = nil,
        photoRelativePath: String? = nil,
        notes: String? = nil,
        isConsumable: Bool,
        stock: Decimal,
        stockUnit: String,
        lowStockThreshold: Decimal? = nil,
        lowStockEnabled: Bool,
        isDevice: Bool,
        isPoweredOn: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.categoryRaw = category.rawValue
        self.brand = brand
        self.specification = specification
        self.purchasedAt = purchasedAt
        self.purchasePrice = purchasePrice
        self.quantity = quantity
        self.location = location
        self.photoRelativePath = photoRelativePath
        self.notes = notes
        self.isConsumable = isConsumable
        self.stock = stock
        self.stockUnit = stockUnit
        self.lowStockThreshold = lowStockThreshold
        self.lowStockEnabled = lowStockEnabled
        self.isDevice = isDevice
        self.isPoweredOn = isPoweredOn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: ToolItem {
        ToolItem(
            id: id,
            name: name,
            category: ToolCategory(rawValue: categoryRaw) ?? .other,
            brand: brand,
            specification: specification,
            purchasedAt: purchasedAt,
            purchasePrice: purchasePrice,
            quantity: quantity,
            location: location,
            photoRelativePath: photoRelativePath,
            notes: notes,
            isConsumable: isConsumable,
            stock: stock,
            stockUnit: stockUnit,
            lowStockThreshold: lowStockThreshold,
            lowStockEnabled: lowStockEnabled,
            isDevice: isDevice,
            isPoweredOn: isPoweredOn,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class ToolPhotoRecord {
    @Attribute(.unique) var id: UUID
    var toolID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        toolID: UUID,
        originalRelativePath: String,
        thumbnailRelativePath: String,
        capturedAt: Date,
        caption: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.toolID = toolID
        self.originalRelativePath = originalRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.capturedAt = capturedAt
        self.caption = caption
        self.createdAt = createdAt
    }

    var domain: ToolPhoto {
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

@Model
final class StockAdjustmentRecord {
    @Attribute(.unique) var id: UUID
    var toolID: UUID
    var modeRaw: String
    var delta: Decimal?
    var resultingStock: Decimal
    var occurredAt: Date
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        toolID: UUID,
        mode: StockAdjustmentMode,
        delta: Decimal?,
        resultingStock: Decimal,
        occurredAt: Date,
        note: String?,
        createdAt: Date
    ) {
        self.id = id
        self.toolID = toolID
        self.modeRaw = mode.rawValue
        self.delta = delta
        self.resultingStock = resultingStock
        self.occurredAt = occurredAt
        self.note = note
        self.createdAt = createdAt
    }

    var domain: StockAdjustment {
        StockAdjustment(
            id: id,
            toolID: toolID,
            mode: StockAdjustmentMode(rawValue: modeRaw) ?? .calibrate,
            delta: delta,
            resultingStock: resultingStock,
            occurredAt: occurredAt,
            note: note,
            createdAt: createdAt
        )
    }
}

// MARK: - Ledger

@Model
final class LedgerEntryRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var categoryRaw: String
    var amount: Decimal
    var currency: String
    var occurredAt: Date
    var platform: String?
    var storeName: String?
    var plantID: UUID?
    var toolID: UUID?
    var note: String?
    var sourceTypeRaw: String?
    var sourceID: UUID?
    var relatedEntryID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: LedgerKind,
        title: String,
        category: LedgerCategory,
        amount: Decimal,
        currency: String = "CNY",
        occurredAt: Date,
        platform: String? = nil,
        storeName: String? = nil,
        plantID: UUID? = nil,
        toolID: UUID? = nil,
        note: String? = nil,
        sourceType: LedgerSourceType? = nil,
        sourceID: UUID? = nil,
        relatedEntryID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.currency = currency
        self.occurredAt = occurredAt
        self.platform = platform
        self.storeName = storeName
        self.plantID = plantID
        self.toolID = toolID
        self.note = note
        self.sourceTypeRaw = sourceType?.rawValue
        self.sourceID = sourceID
        self.relatedEntryID = relatedEntryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: LedgerEntry {
        LedgerEntry(
            id: id,
            kind: LedgerKind(rawValue: kindRaw) ?? .expense,
            title: title,
            category: LedgerCategory(rawValue: categoryRaw) ?? .otherExpense,
            amount: amount,
            currency: currency,
            occurredAt: occurredAt,
            platform: platform,
            storeName: storeName,
            plantID: plantID,
            toolID: toolID,
            note: note,
            sourceType: sourceTypeRaw.flatMap(LedgerSourceType.init(rawValue:)),
            sourceID: sourceID,
            relatedEntryID: relatedEntryID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Import

@Model
final class OrderImportRecordModel {
    @Attribute(.unique) var id: UUID
    var attachmentIDsJSON: String
    var rawOCRText: String
    var recognizedDraftJSON: String
    var status: String
    var orderNumber: String?
    var failureMessage: String?
    var importedPlantID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        attachmentIDsJSON: String,
        rawOCRText: String,
        recognizedDraftJSON: String,
        status: String,
        orderNumber: String?,
        failureMessage: String? = nil,
        importedPlantID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.attachmentIDsJSON = attachmentIDsJSON
        self.rawOCRText = rawOCRText
        self.recognizedDraftJSON = recognizedDraftJSON
        self.status = status
        self.orderNumber = orderNumber
        self.failureMessage = failureMessage
        self.importedPlantID = importedPlantID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var domain: OrderImportRecord {
        OrderImportRecord(
            id: id,
            attachmentIDs: (try? JSONDecoder().decode([UUID].self, from: Data(attachmentIDsJSON.utf8))) ?? [],
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
