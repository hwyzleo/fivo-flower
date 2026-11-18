import Foundation

@MainActor
final class FileBackupService: BackupServicing {
    static let formatVersion = 1

    private let store: FivoDataStore
    private let imageStore: ImageStore
    private let fileManager: FileManager
    private let backupsDirectory: URL
    private let appVersion: String

    init(
        store: FivoDataStore,
        imageStore: ImageStore,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.imageStore = imageStore
        self.fileManager = fileManager
        let documents = baseDirectory ?? (try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        backupsDirectory = documents.appendingPathComponent("Backups", isDirectory: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        appVersion = version ?? "1.0"
    }

    // MARK: - Create

    func createBackup() throws -> URL {
        let snapshot = try store.snapshot()
        let payload = BackupData(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dataJSON: Data
        do {
            dataJSON = try encoder.encode(payload)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }

        var referencedPaths = Set(payload.mediaReferences)
        for photo in snapshot.photos {
            if let cover = imageStore.coverRelativePath(forPhotoID: photo.id) {
                referencedPaths.insert(cover)
            }
        }
        var mediaEntries: [String: Data] = [:]
        var mediaFiles: [String] = []
        for path in referencedPaths.sorted() {
            let url = imageStore.absoluteURL(for: path)
            guard let data = try? Data(contentsOf: url) else { continue }
            mediaEntries[path] = data
            mediaFiles.append(path)
        }

        let manifest = BackupManifest(
            formatVersion: Self.formatVersion,
            appVersion: appVersion,
            createdAt: Date(),
            counts: [
                "plants": snapshot.plants.count,
                "journals": snapshot.journals.count,
                "photos": snapshot.photos.count + snapshot.toolPhotos.count,
                "ledger": snapshot.ledgerEntries.count,
                "tools": snapshot.tools.count,
                "careLogs": snapshot.careLogs.count,
                "reminders": snapshot.reminders.count
            ],
            mediaFiles: mediaFiles
        )
        guard let manifestJSON = try? encoder.encode(manifest) else {
            throw BackupError.writeFailed("manifest 编码失败")
        }

        var entries: [SimpleZip.Entry] = [
            SimpleZip.Entry(path: "manifest.json", data: manifestJSON),
            SimpleZip.Entry(path: "data.json", data: dataJSON)
        ]
        for (path, data) in mediaEntries.sorted(by: { $0.key < $1.key }) {
            entries.append(SimpleZip.Entry(path: "Media/\(path)", data: data))
        }
        let archive = SimpleZip.archive(entries: entries)
        let url = backupsDirectory.appendingPathComponent(backupFileName())
        do {
            try archive.write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
        return url
    }

    // MARK: - Inspect

    func inspectBackup(at url: URL) throws -> BackupSummary {
        let parsed = try parse(url: url)
        return parsed.summary
    }

    // MARK: - Restore

    func restoreBackup(at url: URL) throws -> BackupSummary {
        // 1. 先完整校验，任何问题都不触碰现有数据
        let parsed = try parse(url: url)
        // 2. 替换前自动生成安全备份
        let safety = try? createBackup()
        do {
            try apply(parsed)
            return parsed.summary
        } catch {
            if let safety {
                if let safetyParsed = try? parse(url: safety) {
                    try? apply(safetyParsed)
                }
            }
            throw BackupError.restoreFailed(error.localizedDescription)
        }
    }

    func createSafetyBackup() throws -> URL? {
        try createBackup()
    }

    // MARK: - Internals

    private struct ParsedBackup {
        var manifest: BackupManifest
        var snapshot: BackupDomainSnapshot
        var media: [String: Data]
        var summary: BackupSummary
    }

    private func parse(url: URL) throws -> ParsedBackup {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            throw BackupError.invalidArchive
        }
        let entries: [String: Data]
        do {
            entries = try SimpleZip.extract(data: raw)
        } catch {
            throw BackupError.invalidArchive
        }
        guard let manifestData = entries["manifest.json"], let dataData = entries["data.json"] else {
            throw BackupError.invalidArchive
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData) else {
            throw BackupError.invalidArchive
        }
        guard manifest.formatVersion == Self.formatVersion else {
            throw BackupError.unsupportedVersion(manifest.formatVersion)
        }
        guard let payload = try? decoder.decode(BackupData.self, from: dataData) else {
            throw BackupError.corrupted("data.json 解析失败")
        }
        let snapshot: BackupDomainSnapshot
        do {
            snapshot = try payload.snapshot()
        } catch {
            throw BackupError.corrupted(error.localizedDescription)
        }
        var media: [String: Data] = [:]
        for path in manifest.mediaFiles {
            guard let fileData = entries["Media/\(path)"] else {
                throw BackupError.corrupted("缺少媒体文件 \(path)")
            }
            media[path] = fileData
        }
        let summary = BackupSummary(
            createdAt: manifest.createdAt,
            appVersion: manifest.appVersion,
            formatVersion: manifest.formatVersion,
            plantCount: snapshot.plants.count,
            journalCount: snapshot.journals.count,
            photoCount: snapshot.photos.count + snapshot.toolPhotos.count,
            ledgerCount: snapshot.ledgerEntries.count,
            toolCount: snapshot.tools.count,
            mediaFileCount: media.count
        )
        return ParsedBackup(manifest: manifest, snapshot: snapshot, media: media, summary: summary)
    }

    private func apply(_ parsed: ParsedBackup) throws {
        try store.replaceAll(with: parsed.snapshot)
        try imageStore.deleteAll()
        for (path, data) in parsed.media {
            let url = imageStore.absoluteURL(for: path)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    private func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "FivoFlower-\(formatter.string(from: Date())).fivoflower"
    }
}

// MARK: - CSV

final class FileCSVExporter: CSVExporting {
    private let fileManager: FileManager
    private let exportsDirectory: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let documents = baseDirectory ?? (try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        exportsDirectory = documents.appendingPathComponent("Exports", isDirectory: true)
        try? fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    }

    func exportPlantsCSV(plants: [Plant], categories: [UUID: PlantCategory]) throws -> URL {
        var rows: [String] = []
        rows.append(FivoCSV.line([
            "品种名称", "别名", "植物编号", "规格", "购买日期", "入手价", "平台", "店名",
            "来源链接", "植料", "摆放位置", "生命状态", "分类", "陪伴天数", "备注", "创建时间", "更新时间"
        ]))
        let calculator = PlantDurationCalculator()
        let now = Date()
        for plant in plants {
            rows.append(FivoCSV.line([
                plant.name,
                plant.alias ?? "",
                plant.plantCode ?? "",
                plant.specification ?? "",
                plant.acquiredAt.map(FivoDate.day) ?? "",
                plant.purchasePrice.map(FivoMoney.plainString) ?? "",
                plant.platform ?? "",
                plant.storeName ?? "",
                plant.sourceURL ?? "",
                plant.medium ?? "",
                plant.location ?? "",
                plant.lifeStatus.title,
                categories[plant.id]?.title ?? "",
                calculator.companionDays(for: plant, now: now).map(String.init) ?? "",
                plant.notes ?? "",
                FivoDate.dateTime(plant.createdAt),
                FivoDate.dateTime(plant.updatedAt)
            ]))
        }
        return try write(name: "plants-\(timestamp()).csv", content: rows.joined(separator: "\r\n"))
    }

    func exportLedgerCSV(
        entries: [LedgerEntry],
        plantNames: [UUID: String],
        toolNames: [UUID: String]
    ) throws -> URL {
        var rows: [String] = []
        rows.append(FivoCSV.line([
            "类型", "标题", "分类", "金额", "日期", "平台", "店铺", "关联植物", "关联工具", "关联退款", "备注", "来源"
        ]))
        for entry in entries {
            rows.append(FivoCSV.line([
                entry.kind.title,
                entry.title,
                entry.category.title,
                FivoMoney.plainString(entry.amount),
                FivoDate.day(entry.occurredAt),
                entry.platform ?? "",
                entry.storeName ?? "",
                entry.plantID.flatMap { plantNames[$0] } ?? "",
                entry.toolID.flatMap { toolNames[$0] } ?? "",
                entry.relatedEntryID?.uuidString ?? "",
                entry.note ?? "",
                entry.sourceType?.rawValue ?? "manual"
            ]))
        }
        return try write(name: "ledger-\(timestamp()).csv", content: rows.joined(separator: "\r\n"))
    }

    private func write(name: String, content: String) throws -> URL {
        let url = exportsDirectory.appendingPathComponent(name)
        // Excel 兼容 UTF-8 BOM
        let data = Data(("\u{FEFF}" + content).utf8)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
        return url
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
