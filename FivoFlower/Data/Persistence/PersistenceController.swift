import Foundation
import SwiftData

enum FivoSchema {
    /// 业务 schema 版本，与备份格式版本独立维护。
    static let version = 1
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        PlantRecord.self,
        GrowthStageRecord.self,
        GrowthSessionRecord.self,
        PlantPhotoRecord.self,
        OrderAttachmentRecord.self,
        JournalEntryRecord.self,
        CareActionTypeRecord.self,
        CareLogRecord.self,
        CareReminderRecord.self,
        ToolItemRecord.self,
        ToolPhotoRecord.self,
        StockAdjustmentRecord.self,
        LedgerEntryRecord.self,
        OrderImportRecordModel.self
    ]

    static var schema: Schema {
        Schema(models, version: versionIdentifier)
    }
}

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "FivoFlower",
            schema: FivoSchema.schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: FivoSchema.schema, configurations: [configuration])
    }
}

enum DataError: LocalizedError {
    case notFound(String)
    case validation(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let what): return "未找到\(what)。"
        case .validation(let message): return message
        case .persistence(let message): return "数据保存失败：\(message)"
        }
    }
}
