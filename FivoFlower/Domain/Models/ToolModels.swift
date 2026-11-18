import Foundation

enum ToolCategory: String, Codable, CaseIterable, Identifiable {
    case pot
    case growLight
    case ventilation
    case label
    case shaping
    case medium
    case watering
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pot: return "花盆"
        case .growLight: return "补光灯"
        case .ventilation: return "通风设备"
        case .label: return "标签"
        case .shaping: return "塑形工具"
        case .medium: return "植料"
        case .watering: return "浇水瓶"
        case .other: return "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .pot: return "circle.dashed"
        case .growLight: return "lightbulb"
        case .ventilation: return "fan"
        case .label: return "tag"
        case .shaping: return "scissors"
        case .medium: return "square.stack.3d.up"
        case .watering: return "drop"
        case .other: return "shippingbox"
        }
    }

    var isDeviceCandidate: Bool {
        self == .growLight || self == .ventilation
    }
}

struct ToolItem: Identifiable, Hashable {
    var id: UUID
    var name: String
    var category: ToolCategory
    var brand: String?
    var specification: String?
    var purchasedAt: Date?
    var purchasePrice: Decimal?
    var quantity: Int
    var location: String?
    var photoRelativePath: String?
    var notes: String?
    var isConsumable: Bool
    var stock: Decimal
    var stockUnit: String
    var lowStockThreshold: Decimal?
    var lowStockEnabled: Bool
    var isDevice: Bool
    var isPoweredOn: Bool
    var createdAt: Date
    var updatedAt: Date

    var isLowStock: Bool {
        guard isConsumable, lowStockEnabled, let threshold = lowStockThreshold else { return false }
        return stock <= threshold
    }
}

struct ToolPhoto: Identifiable, Hashable {
    var id: UUID
    var toolID: UUID
    var originalRelativePath: String
    var thumbnailRelativePath: String
    var capturedAt: Date
    var caption: String?
    var createdAt: Date
}

struct ToolDraft: Equatable {
    var name: String = ""
    var category: ToolCategory = .pot
    var brand: String = ""
    var specification: String = ""
    var purchasedAt: Date?
    var purchasePriceText: String = ""
    var quantityText: String = "1"
    var location: String = ""
    var notes: String = ""
    var isConsumable: Bool = false
    var stockText: String = ""
    var stockUnit: String = "包"
    var lowStockThresholdText: String = ""
    var lowStockEnabled: Bool = false
    var isDevice: Bool = false
    var isPoweredOn: Bool = false
    var generateLedger: Bool = false

    init() {}

    init(tool: ToolItem) {
        name = tool.name
        category = tool.category
        brand = tool.brand ?? ""
        specification = tool.specification ?? ""
        purchasedAt = tool.purchasedAt
        if let price = tool.purchasePrice {
            purchasePriceText = FivoMoney.plainString(price)
        }
        quantityText = String(tool.quantity)
        location = tool.location ?? ""
        notes = tool.notes ?? ""
        isConsumable = tool.isConsumable
        stockText = FivoMoney.plainString(tool.stock)
        stockUnit = tool.stockUnit
        if let threshold = tool.lowStockThreshold {
            lowStockThresholdText = FivoMoney.plainString(threshold)
        }
        lowStockEnabled = tool.lowStockEnabled
        isDevice = tool.isDevice
        isPoweredOn = tool.isPoweredOn
    }

    var purchasePrice: Decimal? { FivoMoney.parse(purchasePriceText) }
    var stock: Decimal? { FivoMoney.parse(stockText) }
    var lowStockThreshold: Decimal? { FivoMoney.parse(lowStockThresholdText) }

    var quantity: Int {
        max(1, Int(quantityText.trimmingCharacters(in: .whitespaces)) ?? 1)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ToolFieldError: Equatable {
    case nameRequired
    case priceInvalid
    case stockInvalid
    case thresholdInvalid

    var message: String {
        switch self {
        case .nameRequired: return "请填写工具名称"
        case .priceInvalid: return "价格需为不超过两位小数的非负数"
        case .stockInvalid: return "库存不能为负数"
        case .thresholdInvalid: return "低库存阈值不能为负数"
        }
    }
}

enum ToolValidator {
    static func validate(_ draft: ToolDraft) -> [ToolFieldError] {
        var errors: [ToolFieldError] = []
        if draft.trimmedName.isEmpty { errors.append(.nameRequired) }
        if !draft.purchasePriceText.trimmingCharacters(in: .whitespaces).isEmpty,
           draft.purchasePrice == nil {
            errors.append(.priceInvalid)
        }
        if !draft.stockText.trimmingCharacters(in: .whitespaces).isEmpty,
           draft.stock == nil {
            errors.append(.stockInvalid)
        }
        if !draft.lowStockThresholdText.trimmingCharacters(in: .whitespaces).isEmpty,
           draft.lowStockThreshold == nil {
            errors.append(.thresholdInvalid)
        }
        return errors
    }
}

enum StockAdjustmentMode: String, Codable, CaseIterable, Identifiable {
    case increase
    case decrease
    case calibrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .increase: return "增加"
        case .decrease: return "减少"
        case .calibrate: return "校准为"
        }
    }
}

struct StockAdjustment: Identifiable, Hashable {
    var id: UUID
    var toolID: UUID
    var mode: StockAdjustmentMode
    var delta: Decimal?
    var resultingStock: Decimal
    var occurredAt: Date
    var note: String?
    var createdAt: Date
}

struct StockDraft: Equatable {
    var mode: StockAdjustmentMode = .increase
    var amountText: String = ""
    var note: String = ""

    var amount: Decimal? { FivoMoney.parse(amountText) }
}

enum StockCalculator {
    static func resultingStock(current: Decimal, mode: StockAdjustmentMode, amount: Decimal) throws -> Decimal {
        guard amount >= 0 else { throw StockError.negativeAmount }
        switch mode {
        case .increase:
            return current + amount
        case .decrease:
            let result = current - amount
            guard result >= 0 else { throw StockError.insufficientStock }
            return result
        case .calibrate:
            return amount
        }
    }
}

enum StockError: LocalizedError, Equatable {
    case negativeAmount
    case insufficientStock

    var errorDescription: String? {
        switch self {
        case .negativeAmount: return "调整数量不能为负数"
        case .insufficientStock: return "库存不足，无法减少到负数"
        }
    }
}
