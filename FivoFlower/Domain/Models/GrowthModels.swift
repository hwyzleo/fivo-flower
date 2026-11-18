import Foundation

// MARK: - Stage definitions

enum GrowthStageKey {
    static let leafRoot = "leafRoot"
    static let flowerSpike = "flowerSpike"
    static let bloom = "bloom"

    static let builtInOrder: [String] = [leafRoot, flowerSpike, bloom]

    static func builtInName(for key: String) -> String? {
        switch key {
        case leafRoot: return "养叶养根"
        case flowerSpike: return "出花梗"
        case bloom: return "开花"
        default: return nil
        }
    }

    static func isBuiltIn(_ key: String) -> Bool {
        builtInOrder.contains(key)
    }
}

struct GrowthStage: Identifiable, Hashable {
    var key: String
    var name: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sortOrder: Int
    var colorToken: String

    var id: String { key }

    var isBloom: Bool { key == GrowthStageKey.bloom }
    var isSpike: Bool { key == GrowthStageKey.flowerSpike }
}

// MARK: - Sessions

struct GrowthSession: Identifiable, Hashable {
    var id: UUID
    var plantID: UUID
    var stageKey: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    var isOngoing: Bool { endedAt == nil }
}

struct GrowthSessionSpan: Hashable {
    var stageKey: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
}

enum GrowthSessionError: LocalizedError, Equatable {
    case startInFuture
    case endBeforeStart
    case overlap
    case endInFuture
    case unknownStage

    var errorDescription: String? {
        switch self {
        case .startInFuture: return "开始日期不能晚于当前时间"
        case .endBeforeStart: return "结束日期不能早于开始日期"
        case .overlap: return "状态时间与已有历史重叠，请调整后再保存"
        case .endInFuture: return "结束日期不能晚于当前时间"
        case .unknownStage: return "未找到对应的生长状态"
        }
    }
}

// MARK: - Statistics

struct PlantStatistics: Equatable {
    var spikeCount: Int = 0
    var averageSpikeIntervalDays: Double?
    var mostRecentSpikeAt: Date?
    var bloomCount: Int = 0
    var mostRecentBloomAt: Date?
    var averageBloomDurationDays: Double?
    var longestBloomDurationDays: Int?
    var ongoingBloomDurationDays: Int?

    static let empty = PlantStatistics()

    var hasBloomData: Bool { bloomCount > 0 || ongoingBloomDurationDays != nil }
}

struct YearlyGrowthPoint: Identifiable, Hashable {
    var month: Int
    var spikeCount: Int
    var bloomCount: Int

    var id: Int { month }
}
