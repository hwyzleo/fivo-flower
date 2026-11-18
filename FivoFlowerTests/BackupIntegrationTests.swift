import XCTest
import SwiftData
@testable import FivoFlower

@MainActor
final class BackupIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: FivoDataStore!
    private var imageStore: LocalImageStore!
    private var service: FileBackupService!
    private var tempURL: URL!
    private var clock: MutableClock2!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(string) 12:00")!
    }

    private var tinyImage: ImagePayload {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
        return ImagePayload(data: Data(base64Encoded: base64)!, capturedAt: clock.now)
    }

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FivoBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        imageStore = LocalImageStore(baseDirectory: tempURL.appendingPathComponent("media"))
        clock = MutableClock2(date("2025-06-15"))
        store = FivoDataStore(
            context: container.mainContext,
            imageStore: imageStore,
            now: { [clock] in clock?.now ?? Date() },
            calendar: calendar
        )
        service = FileBackupService(
            store: store,
            imageStore: imageStore,
            baseDirectory: tempURL.appendingPathComponent("documents")
        )
    }

    override func tearDownWithError() throws {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        service = nil
        store = nil
        imageStore = nil
        container = nil
    }

    @discardableResult
    private func seedGarden() throws -> Plant {
        var draft = PlantDraft()
        draft.name = "白锦龟背竹"
        draft.acquiredAt = date("2025-06-01")
        draft.purchasePriceText = "420"
        draft.platform = "闲鱼"
        draft.location = "阳台"
        var options = PlantCreationOptions()
        options.coverPhoto = tinyImage
        var ledger = LedgerDraft()
        ledger.title = "植物采购：白锦龟背竹"
        ledger.amountText = "420"
        ledger.category = .plantPurchase
        ledger.occurredAt = date("2025-06-01")
        ledger.platform = "闲鱼"
        ledger.generateLedger = true
        options.ledgerDraft = ledger
        let plant = try store.createPlant(draft: draft, options: options)

        let action = try store.actionTypes(includeDisabled: false).first { $0.name == "浇水" }!
        _ = try store.recordCare(
            CareRecordDraft(
                plantIDs: [plant.id],
                actionTypeID: action.id,
                occurredAt: clock.now,
                note: "浇透",
                dosage: "",
                unit: "",
                photos: [tinyImage]
            )
        )
        _ = try store.createReminders(
            ReminderDraft(
                plantIDs: [plant.id],
                actionTypeID: action.id,
                title: "浇水",
                dueAt: date("2025-06-20"),
                recurrence: .everyNDays(7)
            )
        )

        var toolDraft = ToolDraft()
        toolDraft.name = "水苔"
        toolDraft.category = .medium
        toolDraft.isConsumable = true
        toolDraft.stockText = "5"
        toolDraft.stockUnit = "包"
        let tool = try store.createTool(draft: toolDraft, photo: tinyImage, ledgerDraft: nil)
        _ = try store.addToolPhotos(
            toolID: tool.id,
            payloads: [tinyImage, tinyImage],
            caption: "使用说明"
        )

        return plant
    }

    func testBackupClearRestoreRoundTrip() throws {
        let plant = try seedGarden()
        let photoCountBefore = try store.allPhotoCount()
        let toolPhotoCountBefore = try store.toolPhotos(toolID: try XCTUnwrap(try store.tools().first).id).count
        XCTAssertEqual(toolPhotoCountBefore, 2)
        let journalCountBefore = try store.snapshot().journals.count
        let ledgerCountBefore = try store.snapshot().ledgerEntries.count

        let backupURL = try service.createBackup()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        let summary = try service.inspectBackup(at: backupURL)
        XCTAssertEqual(summary.formatVersion, 1)
        XCTAssertEqual(summary.plantCount, 1)
        XCTAssertEqual(summary.photoCount, photoCountBefore + toolPhotoCountBefore)
        XCTAssertEqual(summary.ledgerCount, ledgerCountBefore)
        XCTAssertGreaterThan(summary.mediaFileCount, 0)

        try store.clearAllData()
        XCTAssertTrue(try store.fetchPlants().isEmpty)
        XCTAssertEqual(try store.allPhotoCount(), 0)
        XCTAssertEqual(try store.snapshot().journals.count, 0)

        let restored = try service.restoreBackup(at: backupURL)
        XCTAssertEqual(restored.plantCount, 1)

        let plants = try store.fetchPlants()
        XCTAssertEqual(plants.count, 1)
        XCTAssertEqual(plants[0].name, "白锦龟背竹")
        XCTAssertEqual(plants[0].id, plant.id)
        XCTAssertEqual(try store.allPhotoCount(), photoCountBefore)
        XCTAssertEqual(try store.snapshot().journals.count, journalCountBefore)
        XCTAssertEqual(try store.snapshot().ledgerEntries.count, ledgerCountBefore)
        XCTAssertEqual(try store.tools().count, 1)
        XCTAssertEqual(try store.reminders().count, 1)

        let restoredTool = try XCTUnwrap(try store.tools().first)
        let restoredToolPhotos = try store.toolPhotos(toolID: restoredTool.id)
        XCTAssertEqual(restoredToolPhotos.count, toolPhotoCountBefore)
        for photo in restoredToolPhotos {
            XCTAssertTrue(imageStore.exists(relativePath: photo.originalRelativePath))
            XCTAssertTrue(imageStore.exists(relativePath: photo.thumbnailRelativePath))
        }

        let photos = try store.photos(plantID: plant.id)
        XCTAssertEqual(photos.count, photoCountBefore)
        for photo in photos {
            XCTAssertTrue(imageStore.exists(relativePath: photo.originalRelativePath))
            XCTAssertTrue(imageStore.exists(relativePath: photo.thumbnailRelativePath))
        }
    }

    func testCorruptedBackupDoesNotChangeExistingData() throws {
        _ = try seedGarden()
        let backupURL = try service.createBackup()
        let data = try Data(contentsOf: backupURL)
        var corrupted = data
        let index = corrupted.count / 2
        corrupted[index] = corrupted[index] &+ 0xFF
        let corruptedURL = tempURL.appendingPathComponent("corrupted.fivoflower")
        try corrupted.write(to: corruptedURL)

        XCTAssertThrowsError(try service.inspectBackup(at: corruptedURL))
        XCTAssertThrowsError(try service.restoreBackup(at: corruptedURL))
        XCTAssertEqual(try store.fetchPlants().count, 1)
        XCTAssertEqual(try store.snapshot().photos.count, 2)
    }

    func testUnsupportedBackupVersionIsRejected() throws {
        _ = try seedGarden()
        let snapshot = try store.snapshot()
        let payload = BackupData(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifest = BackupManifest(
            formatVersion: 99,
            appVersion: "test",
            createdAt: Date(),
            counts: [:],
            mediaFiles: []
        )
        let archive = SimpleZip.archive(entries: [
            SimpleZip.Entry(path: "manifest.json", data: try encoder.encode(manifest)),
            SimpleZip.Entry(path: "data.json", data: try encoder.encode(payload))
        ])
        let url = tempURL.appendingPathComponent("future.fivoflower")
        try archive.write(to: url)

        XCTAssertThrowsError(try service.inspectBackup(at: url)) { error in
            guard let backupError = error as? BackupError,
                  case .unsupportedVersion(99) = backupError else {
                return XCTFail("应拒绝不支持的版本，实际：\(error)")
            }
        }
    }

    func testZipRoundTripAndPathSafety() throws {
        let entries = [
            SimpleZip.Entry(path: "manifest.json", data: Data("你好".utf8)),
            SimpleZip.Entry(path: "Media/originals/a.jpg", data: Data([0, 1, 2, 255]))
        ]
        let archive = SimpleZip.archive(entries: entries)
        let extracted = try SimpleZip.extract(data: archive)
        XCTAssertEqual(extracted["manifest.json"], Data("你好".utf8))
        XCTAssertEqual(extracted["Media/originals/a.jpg"], Data([0, 1, 2, 255]))
        XCTAssertFalse(SimpleZip.isSafePath("../etc/passwd"))
        XCTAssertFalse(SimpleZip.isSafePath("/absolute"))
        XCTAssertFalse(SimpleZip.isSafePath("Media/../../x"))
        XCTAssertTrue(SimpleZip.isSafePath("Media/originals/a.jpg"))
    }

    func testCSVExportHandlesChineseAndSpecialCharacters() throws {
        _ = try seedGarden()
        let exporter = FileCSVExporter(baseDirectory: tempURL.appendingPathComponent("csv"))
        let plants = try store.fetchPlants()
        let categories = Dictionary(
            uniqueKeysWithValues: plants.map { ($0.id, PlantCategory.activeUnderOneYear) }
        )
        let url = try exporter.exportPlantsCSV(plants: plants, categories: categories)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(3), Data([0xEF, 0xBB, 0xBF]), "CSV 应带 UTF-8 BOM")
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("白锦龟背竹"))
        XCTAssertTrue(text.contains("品种名称"))

        let ledgerRepository: LedgerRepository = store
        let ledgerURL = try exporter.exportLedgerCSV(
            entries: try ledgerRepository.entries(),
            plantNames: Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0.name) }),
            toolNames: [:]
        )
        let ledgerText = String(data: try Data(contentsOf: ledgerURL), encoding: .utf8)!
        XCTAssertTrue(ledgerText.contains("植物采购"))
    }
}

private final class MutableClock2 {
    var now: Date
    init(_ date: Date) { now = date }
}
