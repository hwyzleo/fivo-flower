import Foundation
import UIKit

/// 把 `.fivoflower` 备份包写入用户本人 iCloud 云盘的 Documents 目录。
///
/// 设计约束（SPEC 设计 5.7）：
/// - 只做备份包维度的上传与恢复，不做数据库级实时同步与跨备份合并。
/// - 落盘前先在本地完成 ZIP 组装，再用 `NSFileCoordinator` 移入容器，避免半写文件被同步。
/// - 清理只作用于本机设备名命名的文件，绝不影响其它设备的备份包。
@MainActor
final class CloudBackupService: CloudBackupServicing {
    static let fileExtension = "fivoflower"

    private enum DefaultsKey {
        static let autoBackupEnabled = "cloudBackup.autoBackupEnabled"
        static let lastBackupAt = "cloudBackup.lastBackupAt"
    }

    private let backup: BackupServicing
    private let container: CloudContainerProviding
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let deviceName: (() -> String)?
    private let downloadTimeout: TimeInterval
    private let downloadPollInterval: TimeInterval

    init(
        backup: BackupServicing,
        container: CloudContainerProviding,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        calendar: Calendar = FivoDate.defaultCalendar,
        now: @escaping () -> Date = { Date() },
        deviceName: (() -> String)? = nil,
        downloadTimeout: TimeInterval = 20,
        downloadPollInterval: TimeInterval = 0.25
    ) {
        self.backup = backup
        self.container = container
        self.fileManager = fileManager
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.deviceName = deviceName
        self.downloadTimeout = downloadTimeout
        self.downloadPollInterval = downloadPollInterval
    }

    /// 设备名用于区分不同设备的备份包；未注入时取系统设备名。
    private func resolvedDeviceName() -> String {
        Self.sanitizedDeviceName(deviceName?() ?? UIDevice.current.name)
    }

    // MARK: - Availability

    func availability() -> CloudBackupAvailability {
        guard container.hasICloudAccount else { return .noAccount }
        guard container.containerURL() != nil else { return .driveDisabled }
        return .ready
    }

    // MARK: - Auto backup bookkeeping

    var isAutoBackupEnabled: Bool {
        get { defaults.object(forKey: DefaultsKey.autoBackupEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: DefaultsKey.autoBackupEnabled) }
    }

    func lastBackupDate() -> Date? {
        guard let stamp = defaults.object(forKey: DefaultsKey.lastBackupAt) as? Double else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    func shouldAutoBackup(now: Date) -> Bool {
        guard isAutoBackupEnabled else { return false }
        guard let last = lastBackupDate() else { return true }
        return now.timeIntervalSince(last) >= 24 * 60 * 60
    }

    // MARK: - Upload

    @discardableResult
    func uploadBackup() throws -> CloudBackupItem {
        let directory = try resolvedDirectory()
        let localURL = try backup.createBackup()
        let date = now()
        let device = resolvedDeviceName()
        let name = Self.fileName(deviceName: device, date: date, calendar: calendar)
        let destination = directory.appendingPathComponent(name)

        try coordinatedWrite(to: destination) { target in
            try self.replaceItem(at: target, with: localURL)
        }

        prune(in: directory, device: device, keeping: name)
        defaults.set(date.timeIntervalSince1970, forKey: DefaultsKey.lastBackupAt)

        return CloudBackupItem(
            fileName: name,
            createdAt: date,
            deviceName: device,
            byteSize: fileSize(of: destination),
            isDownloaded: true
        )
    }

    // MARK: - Listing

    func listBackups() throws -> [CloudBackupItem] {
        let directory = try resolvedDirectory()
        return try listItems(in: directory)
    }

    private func listItems(in directory: URL) throws -> [CloudBackupItem] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey],
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            return []
        }

        var items: [CloudBackupItem] = []
        for url in contents {
            let rawName = url.lastPathComponent
            // 未下载的 iCloud 文件以隐藏占位名出现：.<原名>.icloud
            let isPlaceholder = rawName.hasPrefix(".") && rawName.hasSuffix(".icloud")
            let name: String
            if isPlaceholder {
                name = String(rawName.dropFirst().dropLast(".icloud".count))
            } else {
                name = rawName
            }
            guard (name as NSString).pathExtension == Self.fileExtension,
                  let parsed = Self.parse(fileName: name, calendar: calendar) else { continue }

            let size = isPlaceholder ? 0 : fileSize(of: url)
            let downloaded = !isPlaceholder && container.downloadStatus(of: url) != .notDownloaded
            items.append(CloudBackupItem(
                fileName: name,
                createdAt: parsed.date,
                deviceName: parsed.deviceName,
                byteSize: size,
                isDownloaded: downloaded
            ))
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Restore support

    func prepareForRestore(_ item: CloudBackupItem) throws -> URL {
        let directory = try resolvedDirectory()
        let source = directory.appendingPathComponent(item.fileName)
        guard fileManager.fileExists(atPath: source.path) else {
            throw CloudBackupError.missingFile(item.fileName)
        }
        try ensureDownloaded(source)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-restore-\(UUID().uuidString).fivoflower")
        var readError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &readError) { url in
            do {
                if self.fileManager.fileExists(atPath: destination.path) {
                    try self.fileManager.removeItem(at: destination)
                }
                try self.fileManager.copyItem(at: url, to: destination)
            } catch {
                thrown = error
            }
        }
        if let readError { throw CloudBackupError.downloadFailed(readError.localizedDescription) }
        if let thrown { throw CloudBackupError.downloadFailed(thrown.localizedDescription) }
        return destination
    }

    func deleteBackup(_ item: CloudBackupItem) throws {
        let directory = try resolvedDirectory()
        let target = directory.appendingPathComponent(item.fileName)
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &coordinationError) { url in
            do {
                if self.fileManager.fileExists(atPath: url.path) {
                    try self.fileManager.removeItem(at: url)
                }
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw CloudBackupError.deleteFailed(coordinationError.localizedDescription) }
        if let thrown { throw CloudBackupError.deleteFailed(thrown.localizedDescription) }
    }

    // MARK: - Naming

    static func sanitizedDeviceName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let limited = String(cleaned.prefix(32))
        return limited.isEmpty ? "iPhone" : limited
    }

    static func fileName(deviceName: String, date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "fivoflower-\(sanitizedDeviceName(deviceName))-\(formatter.string(from: date)).\(fileExtension)"
    }

    static func parse(fileName: String, calendar: Calendar) -> (deviceName: String, date: Date)? {
        let pattern = "^fivoflower-(.+)-(\\d{8})-(\\d{4})\\.\(fileExtension)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard let match = regex.firstMatch(in: fileName, options: [], range: range),
              match.numberOfRanges == 4,
              let deviceRange = Range(match.range(at: 1), in: fileName),
              let dayRange = Range(match.range(at: 2), in: fileName),
              let timeRange = Range(match.range(at: 3), in: fileName) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = "\(fileName[dayRange])-\(fileName[timeRange])"
        guard let date = formatter.date(from: stamp) else { return nil }
        return (String(fileName[deviceRange]), date)
    }

    // MARK: - Retention

    /// 保留策略：最近 7 份 + 其余按周各保留最早 1 份、最多 4 周。
    static func retainedFileNames(_ items: [CloudBackupItem], calendar: Calendar) -> Set<String> {
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        var kept = Set(sorted.prefix(7).map(\.fileName))

        var weeks: [(key: String, items: [CloudBackupItem])] = []
        for item in sorted.dropFirst(7) {
            let key = weekKey(item.createdAt, calendar: calendar)
            if let index = weeks.firstIndex(where: { $0.key == key }) {
                weeks[index].items.append(item)
            } else {
                weeks.append((key, [item]))
            }
        }
        for week in weeks.prefix(4) {
            if let earliest = week.items.min(by: { $0.createdAt < $1.createdAt }) {
                kept.insert(earliest.fileName)
            }
        }
        return kept
    }

    static func weekKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }

    // MARK: - Internals

    private func resolvedDirectory() throws -> URL {
        guard container.hasICloudAccount else { throw CloudBackupError.noAccount }
        guard let directory = container.containerURL() else { throw CloudBackupError.driveDisabled }
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw Self.mappedWriteError(error)
            }
        }
        return directory
    }

    private func ensureDownloaded(_ url: URL) throws {
        switch container.downloadStatus(of: url) {
        case .downloaded:
            return
        case .notDownloaded, .downloading:
            container.startDownloading(url)
        case .unknown:
            return
        }

        let deadline = Date().addingTimeInterval(downloadTimeout)
        while Date() < deadline {
            if container.downloadStatus(of: url) == .downloaded { return }
            Thread.sleep(forTimeInterval: downloadPollInterval)
        }
        throw CloudBackupError.downloadFailed("文件仍在从 iCloud 下载，请稍后重试。")
    }

    private func coordinatedWrite(to url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { target in
            do { try body(target) } catch { thrown = error }
        }
        if let coordinationError {
            throw CloudBackupError.writeFailed(coordinationError.localizedDescription)
        }
        if let thrown { throw Self.mappedWriteError(thrown) }
    }

    private func replaceItem(at destination: URL, with source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // 跨卷或容器不支持 move 时退化为拷贝 + 删除。
            try fileManager.copyItem(at: source, to: destination)
            try? fileManager.removeItem(at: source)
        }
    }

    private func prune(in directory: URL, device: String, keeping currentName: String) {
        let items = (try? listItems(in: directory)) ?? []
        let mine = items.filter { $0.deviceName == device }
        var kept = Self.retainedFileNames(mine, calendar: calendar)
        kept.insert(currentName)
        for item in mine where !kept.contains(item.fileName) {
            try? deleteBackup(item)
        }
    }

    private func fileSize(of url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func mappedWriteError(_ error: Error) -> CloudBackupError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError {
            return .outOfSpace
        }
        return .writeFailed(error.localizedDescription)
    }
}

// MARK: - Containers

/// 真实 iCloud 容器：`iCloud.net.hwyz.fivo.flowers` 的 Documents 目录。
final class UbiquitousCloudContainer: CloudContainerProviding {
    static let containerIdentifier = "iCloud.net.hwyz.fivo.flowers"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var hasICloudAccount: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    func containerURL() -> URL? {
        guard let root = fileManager.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
            return nil
        }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try? fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    func downloadStatus(of url: URL) -> CloudFileDownloadStatus {
        guard let values = try? url.resourceValues(
            forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        ) else {
            return fileManager.fileExists(atPath: url.path) ? .downloaded : .unknown
        }
        guard values.isUbiquitousItem == true else {
            return fileManager.fileExists(atPath: url.path) ? .downloaded : .unknown
        }
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return .downloaded
        case .notDownloaded:
            return .notDownloaded
        default:
            return .downloading
        }
    }

    func startDownloading(_ url: URL) {
        try? fileManager.startDownloadingUbiquitousItem(at: url)
    }
}

/// 本地目录假容器：真实文件读写但不触碰 iCloud，用于 UI 测试与调试。
final class LocalCloudContainer: CloudContainerProviding {
    private let directory: URL
    private let fileManager: FileManager
    var hasICloudAccount: Bool = true

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func containerURL() -> URL? {
        directory
    }

    func downloadStatus(of url: URL) -> CloudFileDownloadStatus {
        fileManager.fileExists(atPath: url.path) ? .downloaded : .unknown
    }

    func startDownloading(_ url: URL) {}
}
