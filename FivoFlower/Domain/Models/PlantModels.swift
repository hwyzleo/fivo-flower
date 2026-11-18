import Foundation

// MARK: - Life status & category

enum PlantLifeStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case dead
    case gifted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "存活"
        case .dead: return "死亡"
        case .gifted: return "赠送"
        }
    }
}

enum PlantCategory: String, Codable, CaseIterable, Identifiable {
    case activeUnderOneYear
    case activeOneToTwoYears
    case activeOverTwoYears
    case dead
    case gifted
    case unclassified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeUnderOneYear: return "活 1 年"
        case .activeOneToTwoYears: return "活 2 年"
        case .activeOverTwoYears: return "活大于 2 年"
        case .dead: return "死了"
        case .gifted: return "送了"
        case .unclassified: return "未分类"
        }
    }

    var isLifeStatusCategory: Bool {
        self == .dead || self == .gifted
    }
}

// MARK: - Plant

struct Plant: Identifiable, Hashable {
    var id: UUID
    var name: String
    var alias: String?
    var plantCode: String?
    var specification: String?
    var acquiredAt: Date?
    var purchasePrice: Decimal?
    var currency: String
    var platform: String?
    var storeName: String?
    var sourceURL: String?
    var medium: String?
    var location: String?
    var notes: String?
    var lifeStatus: PlantLifeStatus
    var lifeEventAt: Date?
    var lifeEventReason: String?
    var giftRecipient: String?
    var coverPhotoID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var isArchived: Bool { lifeStatus != .active }

    var displayAliasLine: String? {
        guard let alias, !alias.isEmpty else { return nil }
        return alias
    }
}

// MARK: - Draft & validation

struct PlantDraft: Equatable {
    var name: String = ""
    var alias: String = ""
    var plantCode: String = ""
    var specification: String = ""
    var acquiredAt: Date?
    var purchasePriceText: String = ""
    var platform: String = ""
    var storeName: String = ""
    var sourceURL: String = ""
    var medium: String = ""
    var location: String = ""
    var notes: String = ""
    var initialStageKey: String = GrowthStageKey.leafRoot
    var initialStageStartedAt: Date?

    init() {}

    init(plant: Plant) {
        name = plant.name
        alias = plant.alias ?? ""
        plantCode = plant.plantCode ?? ""
        specification = plant.specification ?? ""
        acquiredAt = plant.acquiredAt
        if let price = plant.purchasePrice {
            purchasePriceText = FivoMoney.plainString(price)
        }
        platform = plant.platform ?? ""
        storeName = plant.storeName ?? ""
        sourceURL = plant.sourceURL ?? ""
        medium = plant.medium ?? ""
        location = plant.location ?? ""
        notes = plant.notes ?? ""
    }

    var purchasePrice: Decimal? {
        FivoMoney.parse(purchasePriceText)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PlantFieldError: Equatable {
    case nameRequired
    case priceInvalid
    case urlInvalid
    case dateInFuture

    var message: String {
        switch self {
        case .nameRequired: return "请填写品种名称"
        case .priceInvalid: return "入手价需为不超过两位小数的非负数"
        case .urlInvalid: return "来源链接格式不正确，应以 http:// 或 https:// 开头"
        case .dateInFuture: return "购买日期不能晚于今天"
        }
    }
}

enum PlantValidator {
    static func validate(_ draft: PlantDraft, now: Date) -> [PlantFieldError] {
        var errors: [PlantFieldError] = []
        if draft.trimmedName.isEmpty {
            errors.append(.nameRequired)
        }
        if !draft.purchasePriceText.trimmingCharacters(in: .whitespaces).isEmpty,
           draft.purchasePrice == nil {
            errors.append(.priceInvalid)
        }
        if let url = normalized(draft.sourceURL), !url.isEmpty {
            let lower = url.lowercased()
            let schemeOK = lower.hasPrefix("http://") || lower.hasPrefix("https://")
            if !schemeOK || URL(string: url)?.host?.isEmpty != false {
                errors.append(.urlInvalid)
            }
        }
        if let acquiredAt = draft.acquiredAt,
           FivoDate.startOfDay(acquiredAt) > FivoDate.startOfDay(now) {
            errors.append(.dateInFuture)
        }
        return errors
    }

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Life event draft

struct LifeEventDraft: Equatable {
    var status: PlantLifeStatus
    var date: Date
    var reason: String = ""
    var recipient: String = ""
}

enum LifeEventValidator {
    static func errors(
        draft: LifeEventDraft,
        plant: Plant,
        now: Date
    ) -> [String] {
        errors(draft: draft, acquiredAt: plant.acquiredAt, now: now)
    }

    static func errors(
        draft: LifeEventDraft,
        acquiredAt: Date?,
        now: Date
    ) -> [String] {
        var errors: [String] = []
        if draft.status == .active {
            errors.append("恢复操作不需要填写归档信息")
        }
        if FivoDate.startOfDay(draft.date) > FivoDate.startOfDay(now) {
            errors.append("日期不能晚于今天")
        }
        if let acquiredAt,
           FivoDate.startOfDay(draft.date) < FivoDate.startOfDay(acquiredAt) {
            errors.append("日期不能早于购买日期")
        }
        return errors
    }
}

// MARK: - Filters

struct PlantFilter: Equatable {
    var query: String = ""
    var category: PlantCategory? = nil
    var stageKey: String? = nil
    var platform: String? = nil
    var location: String? = nil
    var sort: PlantSort = .recentlyUpdated

    var activeConditionCount: Int {
        var count = 0
        if category != nil { count += 1 }
        if stageKey != nil { count += 1 }
        if platform != nil { count += 1 }
        if location != nil { count += 1 }
        return count
    }

    var hasConditions: Bool {
        activeConditionCount > 0 || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum PlantSort: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case purchaseDate
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUpdated: return "最近更新"
        case .purchaseDate: return "购买日期"
        case .name: return "名称"
        }
    }
}
