import XCTest
import SwiftData
@testable import FivoFlower

private final class MutableClock {
    var now: Date
    init(_ date: Date) { now = date }
}

@MainActor
final class DataStoreIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: FivoDataStore!
    private var imageStore: LocalImageStore!
    private var tempURL: URL!
    private var clock: MutableClock!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ string: String, time: String = "12:00") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(string) \(time)")!
    }

    private var tinyImage: ImagePayload {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
        let data = Data(base64Encoded: base64)!
        return ImagePayload(data: data, capturedAt: clock.now)
    }

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FivoTests-\(UUID().uuidString)", isDirectory: true)
        imageStore = LocalImageStore(baseDirectory: tempURL)
        clock = MutableClock(date("2025-06-15"))
        store = FivoDataStore(
            context: container.mainContext,
            imageStore: imageStore,
            now: { [clock] in clock?.now ?? Date() },
            calendar: calendar
        )
    }

    override func tearDownWithError() throws {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        store = nil
        imageStore = nil
        container = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func createPlant(
        name: String = "龟背竹",
        price: String = "120.50",
        withPhoto: Bool = false,
        withLedger: Bool = false
    ) throws -> Plant {
        var draft = PlantDraft()
        draft.name = name
        draft.acquiredAt = date("2025-06-01")
        draft.purchasePriceText = price
        draft.platform = "淘宝"
        draft.location = "阳台"
        var options = PlantCreationOptions()
        if withPhoto {
            options.coverPhoto = tinyImage
        }
        if withLedger {
            var ledger = LedgerDraft()
            ledger.title = "植物采购：\(name)"
            ledger.category = .plantPurchase
            ledger.amountText = price
            ledger.occurredAt = date("2025-06-01")
            ledger.generateLedger = true
            options.ledgerDraft = ledger
        }
        return try store.createPlant(draft: draft, options: options)
    }

    private var journalRepo: JournalRepository { store }
    private var ledgerRepo: LedgerRepository { store }
    private var careRepo: CareRepository { store }
    private var reminderRepo: ReminderRepository { store }
    private var toolRepo: ToolRepository { store }
    private var importRepo: ImportRepository { store }

    // MARK: - Create / update

    func testCreatePlantWritesSessionJournalAndLedgerAtomically() throws {
        let plant = try createPlant(withPhoto: true, withLedger: true)

        XCTAssertEqual(try store.fetchPlants().count, 1)
        let sessions = try store.sessions(plantID: plant.id)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.stageKey, GrowthStageKey.leafRoot)
        XCTAssertEqual(sessions.first?.startedAt, clock.now, "未设置开始日期时使用创建时间")
        XCTAssertNil(sessions.first?.endedAt)

        let journals = try journalRepo.entries(plantID: plant.id)
        XCTAssertEqual(journals.count, 1)
        XCTAssertEqual(journals.first?.kind, .plantCreated)

        let ledgerEntries = try ledgerRepo.entries(plantID: plant.id)
        XCTAssertEqual(ledgerEntries.count, 1)
        XCTAssertEqual(ledgerEntries.first?.amount, Decimal(string: "120.5"))
        XCTAssertEqual(ledgerEntries.first?.sourceType, .plant)

        let photos = try store.photos(plantID: plant.id)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(plant.coverPhotoID, photos.first?.id)
        XCTAssertTrue(imageStore.exists(relativePath: photos[0].originalRelativePath))
        XCTAssertTrue(imageStore.exists(relativePath: photos[0].thumbnailRelativePath))
        XCTAssertTrue(try journalRepo.entries(plantID: plant.id).contains { $0.kind == .plantCreated })
    }

    func testCreatePlantUsesSelectedInitialStageStartDate() throws {
        var draft = PlantDraft()
        draft.name = "指定状态日期"
        var options = PlantCreationOptions()
        options.initialStageStartedAt = date("2025-05-20", time: "15:30")

        let plant = try store.createPlant(draft: draft, options: options)
        let session = try store.sessions(plantID: plant.id).first
        XCTAssertEqual(session?.startedAt, date("2025-05-20", time: "00:00"))
        XCTAssertEqual(session?.createdAt, clock.now, "状态开始日期不改变档案创建时间")
    }

    func testCreatePlantRejectsFutureInitialStageStartDate() throws {
        var draft = PlantDraft()
        draft.name = "未来状态日期"
        var options = PlantCreationOptions()
        options.initialStageStartedAt = date("2025-06-16")

        XCTAssertThrowsError(try store.createPlant(draft: draft, options: options))
        XCTAssertTrue(try store.fetchPlants().isEmpty)
    }

    func testCreatePlantDoesNotGenerateZeroAmountPurchaseLedger() throws {
        let plant = try createPlant(price: "0", withLedger: true)
        XCTAssertTrue(try ledgerRepo.entries(plantID: plant.id).isEmpty)
    }

    func testCreatePlantValidationBlocksInvalidData() {
        var draft = PlantDraft()
        XCTAssertThrowsError(try store.createPlant(draft: draft, options: PlantCreationOptions())) { error in
            XCTAssertTrue(error is DataError)
        }
        XCTAssertEqual(try? store.fetchPlants().count, 0)
    }

    func testUpdatePlantLogsFieldSummaryAndSyncsLedgerOnlyWhenAsked() throws {
        let plant = try createPlant(withLedger: true)
        let original = try ledgerRepo.entries(plantID: plant.id).first!

        var draft = PlantDraft(plant: plant)
        draft.location = "窗边"
        draft.purchasePriceText = "200"
        _ = try store.updatePlant(id: plant.id, draft: draft, syncPurchaseLedger: false)

        var ledger = try ledgerRepo.entry(id: original.id)!
        XCTAssertEqual(ledger.amount, Decimal(string: "120.5"), "未确认同步时不得静默修改账本")

        _ = try store.updatePlant(id: plant.id, draft: draft, syncPurchaseLedger: true)
        ledger = try ledgerRepo.entry(id: original.id)!
        XCTAssertEqual(ledger.amount, 200)

        let journals = try journalRepo.entries(plantID: plant.id)
        let updates = journals.filter { $0.kind == .plantUpdated }
        XCTAssertEqual(updates.count, 1, "无字段变化的保存不应重复写日志")
        XCTAssertTrue(updates.allSatisfy { $0.body.contains("摆放位置") || $0.body.contains("入手价") })
        XCTAssertFalse(updates.contains { $0.body.contains("阳台") }, "资料修改日志只保存字段级摘要")
    }

    func testDuplicatePlantClearsPriceAndHistory() throws {
        let plant = try createPlant(withPhoto: true, withLedger: true)
        let copy = try store.duplicatePlant(id: plant.id)
        XCTAssertNotEqual(copy.id, plant.id)
        XCTAssertNil(copy.purchasePrice)
        XCTAssertNil(copy.coverPhotoID)
        XCTAssertTrue(try store.sessions(plantID: copy.id).count == 1)
        XCTAssertTrue(try ledgerRepo.entries(plantID: copy.id).isEmpty)
        XCTAssertEqual(try store.photos(plantID: copy.id).count, 0)
    }

    // MARK: - Growth

    func testStageSwitchingKeepsSingleOngoingAndHistory() throws {
        let plant = try createPlant()
        clock.now = date("2025-06-16")
        try store.switchStage(plantID: plant.id, to: GrowthStageKey.flowerSpike, at: clock.now, note: "第一支", photos: [])
        clock.now = date("2025-06-20")
        try store.switchStage(plantID: plant.id, to: GrowthStageKey.bloom, at: clock.now, note: "", photos: [tinyImage])

        let sessions = try store.sessions(plantID: plant.id)
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.filter { $0.endedAt == nil }.count, 1)
        XCTAssertEqual(sessions.first(where: { $0.endedAt == nil })?.stageKey, GrowthStageKey.bloom)
        XCTAssertEqual(sessions.first(where: { $0.stageKey == GrowthStageKey.flowerSpike })?.note, "第一支")

        let stats = try store.statistics(plantID: plant.id)
        XCTAssertEqual(stats.spikeCount, 1)
        XCTAssertEqual(stats.bloomCount, 1)

        let journals = try journalRepo.entries(plantID: plant.id)
        XCTAssertEqual(journals.filter { $0.kind == .growthChanged }.count, 2)
        XCTAssertEqual(try store.photos(plantID: plant.id).count, 1)
    }

    func testSwitchStageRejectsInvalidDatesAndArchivedPlants() throws {
        let plant = try createPlant()
        XCTAssertThrowsError(
            try store.switchStage(
                plantID: plant.id,
                to: GrowthStageKey.bloom,
                at: date("2025-07-01"),
                note: "",
                photos: []
            )
        )
        try store.setLifeStatus(plantID: plant.id, status: .dead, date: clock.now, reason: nil, recipient: nil)
        XCTAssertThrowsError(
            try store.switchStage(
                plantID: plant.id,
                to: GrowthStageKey.bloom,
                at: clock.now,
                note: "",
                photos: []
            )
        )
    }

    func testUpdateSessionRejectsOverlap() throws {
        let plant = try createPlant()
        clock.now = date("2025-06-16")
        try store.switchStage(plantID: plant.id, to: GrowthStageKey.flowerSpike, at: clock.now, note: "", photos: [])
        let sessions = try store.sessions(plantID: plant.id)
        let first = sessions.first { $0.stageKey == GrowthStageKey.leafRoot }!
        clock.now = date("2025-06-20")
        XCTAssertThrowsError(
            try store.updateSession(
                id: first.id,
                startedAt: date("2025-06-14"),
                endedAt: date("2025-06-18"),
                note: ""
            )
        ) { error in
            XCTAssertEqual(error as? GrowthSessionError, .overlap)
        }
    }

    func testLifeStatusEndsOngoingAndRestoreStartsLeafRoot() throws {
        let plant = try createPlant()
        try store.setLifeStatus(
            plantID: plant.id,
            status: .dead,
            date: date("2025-06-10"),
            reason: "烂根",
            recipient: nil
        )
        let dead = try store.plant(id: plant.id)!
        XCTAssertEqual(dead.lifeStatus, .dead)
        XCTAssertEqual(dead.lifeEventReason, "烂根")
        XCTAssertTrue(try store.sessions(plantID: plant.id).allSatisfy { $0.endedAt != nil })
        XCTAssertEqual(
            PlantClassificationService(calendar: calendar).category(for: dead, now: clock.now),
            .dead
        )

        try store.restore(plantID: plant.id)
        let restored = try store.plant(id: plant.id)!
        XCTAssertEqual(restored.lifeStatus, .active)
        XCTAssertNil(restored.lifeEventAt)
        let sessions = try store.sessions(plantID: plant.id)
        XCTAssertEqual(sessions.filter { $0.endedAt == nil }.count, 1)
        XCTAssertEqual(sessions.first(where: { $0.endedAt == nil })?.stageKey, GrowthStageKey.leafRoot)
        XCTAssertEqual(sessions.count, 2, "恢复后保留原历史并新建状态")
    }

    // MARK: - Delete

    func testDeletePlantRemovesRelatedDataButKeepsLedgerUnlinked() throws {
        let plant = try createPlant(withPhoto: true, withLedger: true)
        let photos = try store.photos(plantID: plant.id)
        let entries = try ledgerRepo.entries(plantID: plant.id)
        XCTAssertEqual(entries.count, 1)

        try store.delete(plantID: plant.id)

        XCTAssertTrue(try store.fetchPlants().isEmpty)
        XCTAssertTrue(try store.photos(plantID: plant.id).isEmpty)
        XCTAssertTrue(try journalRepo.entries(plantID: plant.id).isEmpty)
        XCTAssertFalse(imageStore.exists(relativePath: photos[0].originalRelativePath))

        let keptEntry = try ledgerRepo.entry(id: entries[0].id)
        XCTAssertNotNil(keptEntry)
        XCTAssertNil(keptEntry?.plantID)
        XCTAssertEqual(keptEntry?.title, entries[0].title)
    }

    // MARK: - Care

    func testBatchCareCreatesIndependentLogsWithSharedBatchID() throws {
        let plantA = try createPlant(name: "A")
        let plantB = try createPlant(name: "B")
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!

        let result = try careRepo.recordCare(
            CareRecordDraft(
                plantIDs: [plantA.id, plantB.id],
                actionTypeID: action.id,
                occurredAt: clock.now,
                note: "浇透",
                dosage: "200",
                unit: "ml",
                photos: [tinyImage]
            )
        )
        XCTAssertEqual(result.logs.count, 2)
        XCTAssertNotNil(result.logs.first?.batchID)
        XCTAssertEqual(result.logs[0].batchID, result.logs[1].batchID)
        XCTAssertEqual(try careRepo.logs(plantID: plantA.id).count, 1)
        XCTAssertEqual(try careRepo.logs(plantID: plantB.id).count, 1)
        XCTAssertEqual(try journalRepo.entries(plantID: plantA.id).filter { $0.kind == .care }.count, 1)
        XCTAssertEqual(try store.photos(plantID: plantA.id).count, 1)
    }

    func testBuiltInCareTypesExcludeOther() throws {
        let builtIns = try careRepo.actionTypes(includeDisabled: true).filter(\.isBuiltIn)
        XCTAssertEqual(builtIns.map(\.key), ["repot", "prune", "water", "fertilize", "pest", "fungus"])
        XCTAssertFalse(builtIns.contains { $0.name == "其他" })
    }

    func testReorderCareTypesPersistsSortOrder() throws {
        let custom = try careRepo.addActionType(name: "喷雾")
        let original = try careRepo.actionTypes(includeDisabled: true)
        XCTAssertEqual(original.last?.id, custom.id)

        let reordered = [custom] + original.filter { $0.id != custom.id }.reversed()
        try careRepo.reorderActionTypes(ids: reordered.map(\.id))

        let reloaded = try careRepo.actionTypes(includeDisabled: true)
        XCTAssertEqual(reloaded.map(\.id), reordered.map(\.id))
        XCTAssertEqual(reloaded.map(\.sortOrder), Array(0..<reloaded.count))
    }

    func testRemoveDeprecatedBuiltInCareTypeKeepsLogs() throws {
        let plant = try createPlant()
        let deprecated = CareActionTypeRecord(
            key: "other",
            name: "其他",
            isBuiltIn: true,
            isEnabled: true,
            sortOrder: 99
        )
        container.mainContext.insert(deprecated)
        let log = CareLogRecord(
            plantID: plant.id,
            actionTypeID: deprecated.id,
            actionNameSnapshot: "其他",
            occurredAt: clock.now,
            note: nil,
            dosage: nil,
            unit: nil,
            batchID: nil,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        container.mainContext.insert(log)
        try container.mainContext.save()

        try store.removeDeprecatedBuiltInCareTypes()

        let remaining = try careRepo.actionTypes(includeDisabled: true)
        XCTAssertFalse(remaining.contains { $0.key == "other" })
        XCTAssertEqual(remaining.map(\.sortOrder), Array(0..<remaining.count))
        let logs = try careRepo.logs(plantID: plant.id)
        XCTAssertEqual(logs.count, 1)
        XCTAssertNil(logs[0].actionTypeID)
        XCTAssertEqual(logs[0].actionNameSnapshot, "其他")
    }

    func testDeleteCustomCareTypeKeepsHistorySnapshot() throws {
        let custom = try careRepo.addActionType(name: "喷雾")
        let plant = try createPlant()
        _ = try careRepo.recordCare(
            CareRecordDraft(
                plantIDs: [plant.id],
                actionTypeID: custom.id,
                occurredAt: clock.now,
                note: "",
                dosage: "",
                unit: "",
                photos: []
            )
        )
        try careRepo.deleteActionType(id: custom.id)
        let logs = try careRepo.logs(plantID: plant.id)
        XCTAssertEqual(logs.count, 1)
        XCTAssertNil(logs[0].actionTypeID)
        XCTAssertEqual(logs[0].actionNameSnapshot, "喷雾")
        let builtIn = try careRepo.actionTypes(includeDisabled: true).first { $0.isBuiltIn }!
        XCTAssertThrowsError(try careRepo.deleteActionType(id: builtIn.id))
    }

    func testReminderCompletionCreatesNextOccurrenceAndCareLog() throws {
        let plant = try createPlant()
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "施肥" }!
        let created = try reminderRepo.createReminders(
            ReminderDraft(
                plantIDs: [plant.id],
                actionTypeID: action.id,
                title: "施肥",
                dueAt: clock.now,
                recurrence: .everyNDays(3)
            )
        )
        XCTAssertEqual(created.count, 1)

        let next = try reminderRepo.completeReminder(
            id: created[0].id,
            at: clock.now,
            createCareRecord: true
        )
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.dueAt, calendar.date(byAdding: .day, value: 3, to: clock.now))
        XCTAssertEqual(next?.status, .pending)

        let all = try reminderRepo.reminders()
        XCTAssertEqual(all.filter { $0.status == .completed }.count, 1)
        XCTAssertEqual(all.filter { $0.status == .pending }.count, 1)
        XCTAssertEqual(try careRepo.logs(plantID: plant.id).count, 1)
        XCTAssertEqual(try journalRepo.entries(plantID: plant.id).filter { $0.kind == .care }.count, 1)

    }

    func testUpdateCycleRecomputesPendingDueFromLatestCare() throws {
        let plant = try createPlant()
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!
        _ = try careRepo.recordCare(CareRecordDraft(
            plantIDs: [plant.id], actionTypeID: action.id, occurredAt: date("2025-06-10"),
            note: "", dosage: "", unit: "", photos: []
        ))
        let current = try reminderRepo.createReminders(ReminderDraft(
            plantIDs: [plant.id], actionTypeID: action.id, title: "浇水",
            dueAt: date("2025-06-20"), recurrence: .everyNDays(4)
        ))[0]

        let updated = try reminderRepo.updateReminder(
            id: current.id,
            draft: ReminderDraft(
                plantIDs: [plant.id], actionTypeID: action.id, title: "浇水",
                dueAt: current.dueAt, recurrence: .everyNMonths(1)
            )
        )

        XCTAssertEqual(updated.id, current.id)
        XCTAssertEqual(updated.dueAt, date("2025-07-10"))
        XCTAssertEqual(updated.recurrence, .everyNMonths(1))
        XCTAssertEqual(try reminderRepo.reminders().filter { $0.status == .pending }.count, 1)
    }

    func testManualCareCompletesMatchingPendingAndUsesOperationTimeAsAnchor() throws {
        let plant = try createPlant()
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!
        let current = try reminderRepo.createReminders(ReminderDraft(
            plantIDs: [plant.id], actionTypeID: action.id, title: "浇水",
            dueAt: date("2025-06-17"), recurrence: .everyNDays(4)
        ))[0]

        _ = try careRepo.recordCare(CareRecordDraft(
            plantIDs: [plant.id], actionTypeID: action.id, occurredAt: date("2025-06-15", time: "09:00"),
            note: "手动浇透", dosage: "", unit: "", photos: []
        ))

        let reminders = try reminderRepo.reminders()
        let completed = reminders.first { $0.id == current.id }
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.completedAt, date("2025-06-15", time: "09:00"))
        let next = reminders.first { $0.status == .pending }
        XCTAssertEqual(next?.dueAt, date("2025-06-19", time: "09:00"))
        XCTAssertEqual(try careRepo.logs(plantID: plant.id).count, 1, "手动养护不能额外重复生成养护记录")
    }

    func testBatchCareCompletesCycleIndependentlyForEachPlant() throws {
        let plantA = try createPlant(name: "A")
        let plantB = try createPlant(name: "B")
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!
        let created = try reminderRepo.createReminders(ReminderDraft(
            plantIDs: [plantA.id, plantB.id], actionTypeID: action.id, title: "浇水",
            dueAt: date("2025-06-18"), recurrence: .everyNWeeks(1)
        ))
        XCTAssertEqual(created.count, 2)

        _ = try careRepo.recordCare(CareRecordDraft(
            plantIDs: [plantA.id, plantB.id], actionTypeID: action.id,
            occurredAt: date("2025-06-15"), note: "", dosage: "", unit: "", photos: []
        ))

        let reminders = try reminderRepo.reminders()
        XCTAssertEqual(reminders.filter { $0.status == .completed }.count, 2)
        XCTAssertEqual(reminders.filter { $0.status == .pending }.count, 2)
        XCTAssertTrue(reminders.filter { $0.status == .pending }.allSatisfy { $0.dueAt == date("2025-06-22") })
    }

    func testUnsupportedLegacyCyclesAreRemovedOnStartup() throws {
        let plant = try createPlant()
        let action = try careRepo.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!
        for raw in ["every:4", "once", "weekly:2,4"] {
            let record = CareReminderRecord(
                plantID: plant.id, actionTypeID: action.id, actionNameSnapshot: action.name,
                title: raw, dueAt: clock.now, recurrence: .everyNDays(1), status: .pending,
                createdAt: clock.now, updatedAt: clock.now
            )
            record.recurrenceRaw = raw
            container.mainContext.insert(record)
        }
        try store.save()

        let migrated = FivoDataStore(
            context: container.mainContext,
            imageStore: imageStore,
            now: { [clock] in clock?.now ?? Date() },
            calendar: calendar
        )
        let reminders = try migrated.reminders()
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "every:4")
        XCTAssertEqual(reminders.first?.recurrence, .everyNDays(4))
    }

    // MARK: - Tools / stock

    func testStockAdjustmentAndLowStock() throws {
        var draft = ToolDraft()
        draft.name = "水苔"
        draft.category = .medium
        draft.isConsumable = true
        draft.stockText = "5"
        draft.stockUnit = "包"
        draft.lowStockEnabled = true
        draft.lowStockThresholdText = "2"
        let tool = try toolRepo.createTool(draft: draft, photo: nil, ledgerDraft: nil)

        var adjustment = StockDraft()
        adjustment.mode = .decrease
        adjustment.amountText = "4"
        try toolRepo.adjustStock(toolID: tool.id, draft: adjustment, at: clock.now)
        let updated = try toolRepo.tool(id: tool.id)!
        XCTAssertEqual(updated.stock, 1)
        XCTAssertTrue(updated.isLowStock)

        adjustment.amountText = "5"
        XCTAssertThrowsError(try toolRepo.adjustStock(toolID: tool.id, draft: adjustment, at: clock.now))
        XCTAssertEqual(try toolRepo.stockAdjustments(toolID: tool.id).count, 1)

        adjustment.mode = .calibrate
        adjustment.amountText = "10"
        try toolRepo.adjustStock(toolID: tool.id, draft: adjustment, at: clock.now)
        XCTAssertEqual(try toolRepo.tool(id: tool.id)?.stock, 10)
        XCTAssertFalse(try toolRepo.tool(id: tool.id)!.isLowStock)
    }

    func testToolPhotoGalleryAddAndDelete() throws {
        var draft = ToolDraft()
        draft.name = "补光灯"
        draft.category = .growLight
        let tool = try toolRepo.createTool(draft: draft, photo: nil, ledgerDraft: nil)

        let photos = try toolRepo.addToolPhotos(
            toolID: tool.id,
            payloads: [tinyImage, tinyImage],
            caption: "  安装效果  "
        )
        XCTAssertEqual(photos.count, 2)
        XCTAssertEqual(photos.first?.caption, "安装效果")
        XCTAssertEqual(try toolRepo.toolPhotos(toolID: tool.id).count, 2)
        for photo in photos {
            XCTAssertTrue(imageStore.exists(relativePath: photo.originalRelativePath))
            XCTAssertTrue(imageStore.exists(relativePath: photo.thumbnailRelativePath))
        }

        try toolRepo.deleteToolPhoto(id: photos[0].id)
        XCTAssertEqual(try toolRepo.toolPhotos(toolID: tool.id).count, 1)
        XCTAssertFalse(imageStore.exists(relativePath: photos[0].originalRelativePath))
        XCTAssertFalse(imageStore.exists(relativePath: photos[0].thumbnailRelativePath))

        try toolRepo.deleteTool(id: tool.id)
        XCTAssertTrue(try toolRepo.toolPhotos(toolID: tool.id).isEmpty)
        XCTAssertFalse(imageStore.exists(relativePath: photos[1].originalRelativePath))
        XCTAssertFalse(imageStore.exists(relativePath: photos[1].thumbnailRelativePath))
    }

    func testToolLedgerAndDeletionKeepsLedger() throws {
        var draft = ToolDraft()
        draft.name = "补光灯"
        draft.category = .growLight
        draft.purchasePriceText = "300"
        draft.isDevice = true
        draft.generateLedger = true
        let tool = try toolRepo.createTool(draft: draft, photo: nil, ledgerDraft: nil)
        let entries = try ledgerRepo.entries(toolID: tool.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.amount, 300)

        try toolRepo.setPowerState(id: tool.id, isOn: true)
        XCTAssertEqual(try toolRepo.tool(id: tool.id)?.isPoweredOn, true)

        try toolRepo.deleteTool(id: tool.id)
        XCTAssertNil(try toolRepo.tool(id: tool.id))
        let kept = try ledgerRepo.entry(id: entries[0].id)
        XCTAssertNotNil(kept)
        XCTAssertNil(kept?.toolID)
    }

    // MARK: - Import

    func testImportRecordMarksCompletedAndFindsDuplicates() throws {
        var draft = OrderDraft()
        draft.plantName = "白锦龟背竹"
        draft.orderNumber = "ORDER-1"
        draft.amountText = "420"
        let recordID = try importRepo.createImportRecord(rawOCRText: "订单 ORDER-1 实付 420", draft: draft)

        var plantDraft = PlantDraft()
        plantDraft.name = "白锦龟背竹"
        plantDraft.purchasePriceText = "420"
        var options = PlantCreationOptions()
        options.importRecordID = recordID
        let plant = try store.createPlant(draft: plantDraft, options: options)

        let record = try importRepo.importRecord(id: recordID)
        XCTAssertEqual(record?.status, "completed")
        XCTAssertEqual(record?.importedPlantID, plant.id)

        let duplicates = try importRepo.duplicateCandidates(
            orderNumber: "ORDER-1",
            attachmentIDs: [],
            rawOCRText: "任意"
        )
        XCTAssertEqual(duplicates.count, 1)
    }
}
