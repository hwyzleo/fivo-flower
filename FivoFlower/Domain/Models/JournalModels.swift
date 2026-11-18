import Foundation

enum JournalKind: String, Codable, CaseIterable, Identifiable {
    case plantCreated
    case plantUpdated
    case growthChanged
    case care
    case photoAdded
    case lifeStatusChanged
    case restored
    case manual
    case orderImported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plantCreated: return "新建档案"
        case .plantUpdated: return "资料修改"
        case .growthChanged: return "状态变化"
        case .care: return "养护"
        case .photoAdded: return "照片"
        case .lifeStatusChanged: return "生命状态"
        case .restored: return "恢复档案"
        case .manual: return "手动日志"
        case .orderImported: return "订单导入"
        }
    }

    var symbolName: String {
        switch self {
        case .plantCreated: return "leaf"
        case .plantUpdated: return "square.and.pencil"
        case .growthChanged: return "arrow.triangle.2.circlepath"
        case .care: return "drop"
        case .photoAdded: return "photo"
        case .lifeStatusChanged: return "heart.slash"
        case .restored: return "arrow.uturn.backward"
        case .manual: return "text.alignleft"
        case .orderImported: return "doc.text.magnifyingglass"
        }
    }

    var isAutomatic: Bool { self != .manual }
}

enum JournalSourceType: String, Codable {
    case plant
    case growthSession
    case careLog
    case photo
    case lifeEvent
    case orderImport
    case manual
}

struct JournalEntry: Identifiable, Hashable {
    var id: UUID
    var plantID: UUID
    var kind: JournalKind
    var occurredAt: Date
    var title: String
    var body: String
    var sourceType: JournalSourceType?
    var sourceID: UUID?
    var isManual: Bool
    var createdAt: Date
    var updatedAt: Date

    var sourceIsDeleted: Bool {
        isManual == false && sourceType == nil
    }
}

struct JournalFilter: Equatable {
    var plantID: UUID?
    var kind: JournalKind?
    var startDate: Date?
    var endDate: Date?

    var isActive: Bool {
        plantID != nil || kind != nil || startDate != nil || endDate != nil
    }
}

// MARK: - Photos

enum PhotoSourceType: String, Codable, CaseIterable {
    case plant
    case growth
    case care
    case journal
    case order

    var title: String {
        switch self {
        case .plant: return "档案"
        case .growth: return "生长状态"
        case .care: return "养护"
        case .journal: return "日志"
        case .order: return "订单截图"
        }
    }
}

struct PlantPhoto: Identifiable, Hashable {
    var id: UUID
    var plantID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var sourceType: PhotoSourceType
    var sourceID: UUID?
    var coverCropData: Data?
    var createdAt: Date

    var isOrderAttachment: Bool { sourceType == .order }
}

enum JournalPhotoAssociation {
    static func photos(for entry: JournalEntry, in plantPhotos: [PlantPhoto]) -> [PlantPhoto] {
        guard let sourceID = entry.sourceID else { return [] }
        let matched: [PlantPhoto]
        switch entry.sourceType {
        case .careLog:
            matched = plantPhotos.filter { $0.sourceType == .care && $0.sourceID == sourceID }
        case .growthSession:
            matched = plantPhotos.filter { $0.sourceType == .growth && $0.sourceID == sourceID }
        case .manual:
            matched = plantPhotos.filter { $0.sourceType == .journal && $0.sourceID == sourceID }
        case .orderImport:
            matched = plantPhotos.filter { $0.sourceType == .order && $0.sourceID == sourceID }
        case .photo:
            matched = plantPhotos.filter { $0.id == sourceID }
        default:
            matched = []
        }
        return matched.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct ImagePayload: Hashable {
    var data: Data
    var capturedAt: Date
}

struct CoverCrop: Codable, Equatable {
    var offsetX: Double
    var offsetY: Double
    var scale: Double
}
