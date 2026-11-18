import Foundation

// MARK: - Images

struct SavedImage: Hashable {
    var originalRelativePath: String
    var thumbnailRelativePath: String
}

protocol ImageStore {
    var mediaDirectory: URL { get }

    func saveImage(data: Data) throws -> SavedImage
    func saveCoverImage(data: Data, photoID: UUID) throws -> String
    func absoluteURL(for relativePath: String) -> URL
    func exists(relativePath: String) -> Bool
    func delete(relativePath: String) throws
    func deleteAll() throws
    func coverRelativePath(forPhotoID photoID: UUID) -> String?
    func loadThumbnailData(relativePath: String) -> Data?
}

enum ImageStoreError: LocalizedError {
    case invalidImageData
    case writeFailed(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData: return "图片数据无法读取"
        case .writeFailed(let detail): return "图片写入失败：\(detail)"
        case .missingFile(let path): return "图片文件缺失：\(path)"
        }
    }
}

// MARK: - OCR

protocol OCRServicing {
    func recognizeText(in imageData: Data) async throws -> String
}

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取截图，请重新选择。"
        case .noTextFound: return "截图中未识别到文字，可手动填写。"
        case .failed(let detail): return "文字识别失败：\(detail)"
        }
    }
}

// MARK: - Notifications

enum NotificationAuthorization: Equatable {
    case notDetermined
    case denied
    case authorized
}

protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func schedule(_ reminder: CareReminder) async
    func cancel(identifier: String) async
    func reconcile(_ reminders: [CareReminder]) async
}

// MARK: - Backup & export

struct BackupSummary: Equatable {
    var createdAt: Date
    var appVersion: String
    var formatVersion: Int
    var plantCount: Int
    var journalCount: Int
    var photoCount: Int
    var ledgerCount: Int
    var toolCount: Int
    var mediaFileCount: Int
}

@MainActor
protocol BackupServicing {
    func createBackup() throws -> URL
    func inspectBackup(at url: URL) throws -> BackupSummary
    func restoreBackup(at url: URL) throws -> BackupSummary
    func createSafetyBackup() throws -> URL?
}

enum BackupError: LocalizedError {
    case invalidArchive
    case unsupportedVersion(Int)
    case corrupted(String)
    case writeFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "备份文件格式不正确或已损坏。"
        case .unsupportedVersion(let version): return "备份版本 \(version) 不受当前 App 支持。"
        case .corrupted(let detail): return "备份内容校验失败：\(detail)"
        case .writeFailed(let detail): return "备份写入失败：\(detail)"
        case .restoreFailed(let detail): return "恢复失败，现有数据未改变：\(detail)"
        }
    }
}

protocol CSVExporting {
    func exportPlantsCSV(plants: [Plant], categories: [UUID: PlantCategory]) throws -> URL
    func exportLedgerCSV(entries: [LedgerEntry], plantNames: [UUID: String], toolNames: [UUID: String]) throws -> URL
}

// MARK: - App environment value bundle

struct PlantCategoryCount: Identifiable, Hashable {
    var category: PlantCategory
    var count: Int

    var id: PlantCategory { category }
}
