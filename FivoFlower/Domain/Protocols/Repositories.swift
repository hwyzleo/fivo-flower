import Foundation

// MARK: - Repository protocols

@MainActor
protocol PlantRepository {
    func fetchPlants() throws -> [Plant]
    func plant(id: UUID) throws -> Plant?
    func createPlant(draft: PlantDraft, options: PlantCreationOptions) throws -> Plant
    func updatePlant(id: UUID, draft: PlantDraft, syncPurchaseLedger: Bool) throws -> Plant
    func duplicatePlant(id: UUID) throws -> Plant
    func setLifeStatus(plantID: UUID, status: PlantLifeStatus, date: Date, reason: String?, recipient: String?) throws
    func restore(plantID: UUID) throws
    func delete(plantID: UUID) throws
    func addManualJournal(plantID: UUID, occurredAt: Date, text: String, photos: [ImagePayload]) throws
}

struct PlantCreationOptions {
    var initialStageKey: String = GrowthStageKey.leafRoot
    var initialStageStartedAt: Date?
    var coverPhoto: ImagePayload?
    var orderAttachments: [ImagePayload] = []
    var ledgerDraft: LedgerDraft?
    var importRecordID: UUID?
    var initialJournalBody: String?
}

@MainActor
protocol GrowthRepository {
    func stages(includeDisabled: Bool) throws -> [GrowthStage]
    func stage(key: String) throws -> GrowthStage?
    func addStage(name: String) throws -> GrowthStage
    func renameStage(key: String, name: String) throws
    func setStageEnabled(key: String, enabled: Bool) throws
    func deleteStage(key: String) throws
    func sessions(plantID: UUID) throws -> [GrowthSession]
    func currentSession(plantID: UUID) throws -> GrowthSession?
    func switchStage(plantID: UUID, to stageKey: String, at date: Date, note: String, photos: [ImagePayload]) throws
    func updateSession(id: UUID, startedAt: Date, endedAt: Date?, note: String) throws
    func statistics(plantID: UUID) throws -> PlantStatistics
}

@MainActor
protocol PhotoRepository {
    func photos(plantID: UUID) throws -> [PlantPhoto]
    func photo(id: UUID) throws -> PlantPhoto?
    func addPhotos(plantID: UUID, payloads: [ImagePayload], source: PhotoSourceType, sourceID: UUID?, caption: String?) throws -> [PlantPhoto]
    func setCover(plantID: UUID, photoID: UUID, croppedImageData: Data?) throws
    func replaceCover(plantID: UUID, payload: ImagePayload) throws -> PlantPhoto
    func deletePhoto(id: UUID) throws
    func allPhotoCount() throws -> Int
}

@MainActor
protocol JournalRepository {
    func entries(plantID: UUID?) throws -> [JournalEntry]
    func filtered(_ filter: JournalFilter) throws -> [JournalEntry]
    func deleteManualEntry(id: UUID) throws
}

@MainActor
protocol CareRepository {
    func actionTypes(includeDisabled: Bool) throws -> [CareActionType]
    func addActionType(name: String) throws -> CareActionType
    func renameActionType(id: UUID, name: String) throws
    func setActionTypeEnabled(id: UUID, enabled: Bool) throws
    func reorderActionTypes(ids: [UUID]) throws
    func deleteActionType(id: UUID) throws
    func recentLogCount(plantID: UUID, limit: Int) throws -> Int
    func logs(plantID: UUID?) throws -> [CareLog]
    func recordCare(_ draft: CareRecordDraft) throws -> CareBatchResult
}

@MainActor
protocol ReminderRepository {
    func reminders() throws -> [CareReminder]
    func pendingReminderCount() throws -> Int
    func createReminders(_ draft: ReminderDraft) throws -> [CareReminder]
    func updateReminder(id: UUID, draft: ReminderDraft) throws -> CareReminder
    func completeReminder(id: UUID, at date: Date, createCareRecord: Bool) throws -> CareReminder?
    func deleteReminder(id: UUID) throws
}

@MainActor
protocol ToolRepository {
    func tools() throws -> [ToolItem]
    func tool(id: UUID) throws -> ToolItem?
    func createTool(draft: ToolDraft, photo: ImagePayload?, ledgerDraft: LedgerDraft?) throws -> ToolItem
    func updateTool(id: UUID, draft: ToolDraft) throws -> ToolItem
    func replacePhoto(toolID: UUID, payload: ImagePayload) throws
    func setPowerState(id: UUID, isOn: Bool) throws
    func adjustStock(toolID: UUID, draft: StockDraft, at date: Date) throws
    func stockAdjustments(toolID: UUID) throws -> [StockAdjustment]
    func toolPhotos(toolID: UUID) throws -> [ToolPhoto]
    func addToolPhotos(toolID: UUID, payloads: [ImagePayload], caption: String?) throws -> [ToolPhoto]
    func deleteToolPhoto(id: UUID) throws
    func deleteTool(id: UUID) throws
}

@MainActor
protocol LedgerRepository {
    func entries() throws -> [LedgerEntry]
    func entry(id: UUID) throws -> LedgerEntry?
    func createEntry(_ draft: LedgerDraft) throws -> LedgerEntry
    func updateEntry(id: UUID, draft: LedgerDraft) throws -> LedgerEntry
    func deleteEntry(id: UUID) throws
    func entries(plantID: UUID?) throws -> [LedgerEntry]
    func entries(toolID: UUID?) throws -> [LedgerEntry]
}

@MainActor
protocol ImportRepository {
    func createImportRecord(rawOCRText: String, draft: OrderDraft) throws -> UUID
    func updateImportRecord(id: UUID, status: String, failureMessage: String?, plantID: UUID?) throws
    func importRecord(id: UUID) throws -> OrderImportRecord?
    func duplicateCandidates(orderNumber: String, attachmentIDs: [UUID], rawOCRText: String) throws -> [OrderImportRecord]
    func clearUnfinishedImports() throws
}

struct OrderImportRecord: Identifiable, Hashable {
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
}
