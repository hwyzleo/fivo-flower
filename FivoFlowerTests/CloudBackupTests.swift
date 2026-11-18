import XCTest
import SwiftData
@testable import FivoFlower

@MainActor
final class CloudBackupTests: XCTestCase {
    private var container: ModelContainer!
    private var store: FivoDataStore!
    private var imageStore: LocalImageStore!
    private var localBackup: FileBackupService!
    private var cloudContainer: FakeCloudContainer!
    private var service: CloudBackupService!
    private var tempURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
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

    private var cloudDirectory: URL {
        tempURL.appendingPathComponent("icloud", isDirectory: true)
    }

    override func setUpWithError() throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FivoCloudTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        imageStore = LocalImageStore(baseDirectory: tempURL.appendingPathComponent("media"))
        clock = MutableClock2(date("2025-06-15"))
        store = FivoDataStore(
            context: container.mainContext,
            imageStore: imageStore,
            now: { [clock] in clock?.now ?? Date() },
            calendar: calendar
        )
        localBackup = FileBackupService(
            store: store,
            imageStore: imageStore,
            baseDirectory: tempURL.appendingPathComponent("documents")
        )
        cloudContainer = FakeCloudContainer(
            directory: cloudDirectory,
            fileManager: .default
        )
        suiteName = "CloudBackupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = CloudBackupService(
            backup: localBackup,
            container: cloudContainer,
            defaults: defaults,
            calendar: calendar,
            now: { [clock] in clock?.now ?? Date() },
            deviceName: { "iPhone 15" },
            downloadTimeout: 0.1,
            downloadPollInterval: 0.01
        )
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        service = nil
        cloudContainer = nil
        localBackup = nil
        store = nil
        imageStore = nil
        container = nil
    }

    @discardableResult
    private func seedPlant() throws -> Plant {
        var draft = PlantDraft()
        draft.name = "白锦龟背竹"
        draft.acquiredAt = date("2025-06-01")
        draft.purchasePriceText = "420"
        draft.platform = "闲鱼"
        draft.location = "阳台"
        var options = PlantCreationOptions()
        options.coverPhoto = tinyImage
        return try store.createPlant(draft: draft, options: options)
    }

    // MARK: - 命名与上传

    func testUploadCreatesNamedPackageInCloudDirectory() throws {
        try seedPlant()
        let item = try service.uploadBackup()

        XCTAssertEqual(item.fileName, "fivoflower-iPhone-15-20250615-1200.fivoflower")
        XCTAssertEqual(item.deviceName, "iPhone-15")
        XCTAssertTrue(item.isDownloaded)
        XCTAssertGreaterThan(item.byteSize, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: cloudDirectory.appendingPathComponent(item.fileName).path
            )
        )
        XCTAssertNotNil(service.lastBackupDate())
    }

    func testUploadRemovesLocalArtifactAndKeepsPackageReadable() throws {
        try seedPlant()
        let item = try service.uploadBackup()
        let url = cloudDirectory.appendingPathComponent(item.fileName)
        let summary = try localBackup.inspectBackup(at: url)
        XCTAssertEqual(summary.plantCount, 1)
    }

    func testSameMinuteUploadReplacesInsteadOfDuplicating() throws {
        try seedPlant()
        let first = try service.uploadBackup()
        let second = try service.uploadBackup()
        XCTAssertEqual(first.fileName, second.fileName)
        XCTAssertEqual(try service.listBackups().count, 1)
    }

    func testListIgnoresUnrelatedFiles() throws {
        try seedPlant()
        _ = try service.uploadBackup()
        try Data("x".utf8).write(to: cloudDirectory.appendingPathComponent("readme.txt"))
        try Data("x".utf8).write(to: cloudDirectory.appendingPathComponent("fivoflower-broken.fivoflower"))

        let items = try service.listBackups()
        XCTAssertEqual(items.count, 1)
    }

    // MARK: - 保留策略

    func testRetainedFileNamesKeepsRecentSevenAndWeeklyEarliest() {
        let dates = [
            "2025-06-02", "2025-06-03", "2025-06-04", "2025-06-05",
            "2025-06-09", "2025-06-10", "2025-06-11", "2025-06-12",
            "2025-06-16", "2025-06-17", "2025-06-18", "2025-06-20"
        ]
        let items = dates.enumerated().map { index, day -> CloudBackupItem in
            let stamp = date(day)
            return CloudBackupItem(
                fileName: CloudBackupService.fileName(deviceName: "iPhone 15", date: stamp, calendar: calendar),
                createdAt: stamp,
                deviceName: "iPhone 15",
                byteSize: 1,
                isDownloaded: true
            )
        }
        let kept = CloudBackupService.retainedFileNames(items, calendar: calendar)
        // 最近 7 份 + 每周最早 1 份（最多 4 周）=> 7 + 2
        XCTAssertEqual(kept.count, 9)
        XCTAssertTrue(kept.contains(items[11].fileName)) // 06-20
        XCTAssertTrue(kept.contains(items[8].fileName))  // 06-16
        XCTAssertTrue(kept.contains(items[7].fileName))  // 06-12
        XCTAssertTrue(kept.contains(items[4].fileName))  // 06-09（上一周最早）
        XCTAssertTrue(kept.contains(items[0].fileName))  // 06-02（更早一周最早）
        XCTAssertFalse(kept.contains(items[1].fileName))
    }

    func testPruneOnlyTouchesOwnDevice() throws {
        try seedPlant()
        let other = CloudBackupService.fileName(
            deviceName: "iPad Pro",
            date: date("2025-05-01"),
            calendar: calendar
        )
        try Data("other-device".utf8).write(to: cloudDirectory.appendingPathComponent(other))

        for day in ["2025-06-02", "2025-06-03", "2025-06-04", "2025-06-05",
                    "2025-06-09", "2025-06-10", "2025-06-11", "2025-06-12",
                    "2025-06-16", "2025-06-17", "2025-06-18"] {
            let stamp = date(day)
            let name = CloudBackupService.fileName(deviceName: "iPhone 15", date: stamp, calendar: calendar)
            try Data("dummy".utf8).write(to: cloudDirectory.appendingPathComponent(name))
        }

        _ = try service.uploadBackup()

        let remaining = try service.listBackups()
        XCTAssertEqual(remaining.filter { $0.deviceName == "iPhone-15" }.count, 9)
        XCTAssertEqual(remaining.filter { $0.deviceName == "iPad-Pro" }.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: cloudDirectory.appendingPathComponent(other).path
            )
        )
    }

    // MARK: - 可用性与降级

    func testAvailabilityReportsMissingAccount() {
        cloudContainer.hasICloudAccount = false
        XCTAssertEqual(service.availability(), .noAccount)
        XCTAssertThrowsError(try service.uploadBackup())
        XCTAssertThrowsError(try service.listBackups())
    }

    func testAvailabilityReportsDisabledDrive() {
        cloudContainer.hasICloudAccount = true
        cloudContainer.directory = nil
        XCTAssertEqual(service.availability(), .driveDisabled)
        XCTAssertThrowsError(try service.uploadBackup())
    }

    func testPrepareForRestoreFailsWhenStillDownloading() throws {
        try seedPlant()
        let item = try service.uploadBackup()
        cloudContainer.status = .notDownloaded
        XCTAssertThrowsError(try service.prepareForRestore(item)) { error in
            XCTAssertTrue(error is CloudBackupError)
        }
        XCTAssertEqual(cloudContainer.startedDownloads, 1)
    }

    func testPrepareForRestoreFailsWhenRemoteFileDeleted() throws {
        try seedPlant()
        let item = try service.uploadBackup()
        try FileManager.default.removeItem(at: cloudDirectory.appendingPathComponent(item.fileName))
        XCTAssertThrowsError(try service.prepareForRestore(item)) { error in
            guard case CloudBackupError.missingFile = error else {
                return XCTFail("期望 missingFile，实际 \(error)")
            }
        }
    }

    func testRestoreFromCloudRoundTrip() throws {
        try seedPlant()
        let item = try service.uploadBackup()

        try store.clearAllData()
        XCTAssertEqual(try store.fetchPlants().count, 0)

        let localCopy = try service.prepareForRestore(item)
        let summary = try localBackup.restoreBackup(at: localCopy)
        XCTAssertEqual(summary.plantCount, 1)
        XCTAssertEqual(try store.fetchPlants().count, 1)
    }

    func testDeleteBackupRemovesCloudFile() throws {
        try seedPlant()
        let item = try service.uploadBackup()
        try service.deleteBackup(item)
        XCTAssertTrue(try service.listBackups().isEmpty)
    }

    // MARK: - 自动备份

    func testAutoBackupRequiresToggleAnd24Hours() {
        XCTAssertFalse(service.shouldAutoBackup(now: date("2025-06-15")))
        service.isAutoBackupEnabled = true
        XCTAssertTrue(service.shouldAutoBackup(now: date("2025-06-15")))

        XCTAssertNoThrow(try seedPlant())
        XCTAssertNoThrow(try service.uploadBackup())
        XCTAssertFalse(service.shouldAutoBackup(now: date("2025-06-16").addingTimeInterval(-60)))
        XCTAssertTrue(service.shouldAutoBackup(now: date("2025-06-16")))
    }

    // MARK: - 命名

    func testSanitizeDeviceNameStripsUnsafeCharacters() {
        XCTAssertEqual(CloudBackupService.sanitizedDeviceName("张三的 iPhone/15"), "张三的-iPhone-15")
        XCTAssertEqual(CloudBackupService.sanitizedDeviceName("   "), "iPhone")
    }
}

// MARK: - 测试替身

private final class MutableClock2 {
    var now: Date
    init(_ date: Date) { now = date }
}

private final class FakeCloudContainer: CloudContainerProviding {
    var hasICloudAccount = true
    var directory: URL?
    var status: CloudFileDownloadStatus = .downloaded
    var startedDownloads = 0

    private let fileManager: FileManager

    init(directory: URL?, fileManager: FileManager) {
        self.directory = directory
        self.fileManager = fileManager
        if let directory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func containerURL() -> URL? {
        directory
    }

    func downloadStatus(of url: URL) -> CloudFileDownloadStatus {
        status
    }

    func startDownloading(_ url: URL) {
        startedDownloads += 1
    }
}
