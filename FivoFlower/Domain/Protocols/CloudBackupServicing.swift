import Foundation

/// iCloud 云盘备份的可用性。设计见 SPEC 设计 5.7。
enum CloudBackupAvailability: Equatable {
    case ready
    case noAccount
    case driveDisabled
    case unavailable(String)
}

/// 云端备份包摘要：列表只读元信息，不加载整包内容。
struct CloudBackupItem: Identifiable, Equatable {
    var fileName: String
    var createdAt: Date
    var deviceName: String
    var byteSize: Int64
    var isDownloaded: Bool

    var id: String { fileName }
}

enum CloudBackupError: LocalizedError {
    case noAccount
    case driveDisabled
    case outOfSpace
    case missingFile(String)
    case downloadFailed(String)
    case writeFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "未登录 iCloud，无法备份到 iCloud 云盘。请在系统设置中登录 Apple ID。"
        case .driveDisabled:
            return "iCloud 云盘未开启。请在系统设置中打开「iCloud 云盘」。"
        case .outOfSpace:
            return "iCloud 空间不足。请清理 iCloud 云盘中的旧备份或其它文件后重试。"
        case .missingFile(let name):
            return "云端备份 \(name) 已不存在，可能已在其它设备删除。"
        case .downloadFailed(let detail):
            return "从 iCloud 下载备份失败：\(detail)"
        case .writeFailed(let detail):
            return "写入 iCloud 云盘失败：\(detail)"
        case .deleteFailed(let detail):
            return "删除云端备份失败：\(detail)"
        }
    }
}

/// 云端备份服务边界：只做备份包维度的上传与恢复，不做数据库级实时同步。
@MainActor
protocol CloudBackupServicing: AnyObject {
    /// 是否允许退到后台时自动备份（距上次成功超过 24 小时才触发）。
    var isAutoBackupEnabled: Bool { get set }

    func availability() -> CloudBackupAvailability
    func lastBackupDate() -> Date?
    func shouldAutoBackup(now: Date) -> Bool

    @discardableResult
    func uploadBackup() throws -> CloudBackupItem
    func listBackups() throws -> [CloudBackupItem]

    /// 确保文件在本地可读：必要时触发 iCloud 下载，返回可解析的本地副本。
    func prepareForRestore(_ item: CloudBackupItem) throws -> URL
    func deleteBackup(_ item: CloudBackupItem) throws
}

/// iCloud 文件下载状态。
enum CloudFileDownloadStatus: Equatable {
    case downloaded
    case downloading
    case notDownloaded
    case unknown
}

/// 隔离 iCloud 容器访问，便于注入假容器做自动化测试。
protocol CloudContainerProviding: AnyObject {
    var hasICloudAccount: Bool { get }
    func containerURL() -> URL?
    func downloadStatus(of url: URL) -> CloudFileDownloadStatus
    func startDownloading(_ url: URL)
}
