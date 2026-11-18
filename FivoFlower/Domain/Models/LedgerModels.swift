import Foundation

enum LedgerKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case income
    case refund

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .refund: return "退款"
        }
    }
}

enum LedgerCategory: String, Codable, CaseIterable, Identifiable {
    case plantPurchase
    case toolPurchase
    case medium
    case careSupply
    case equipment
    case otherExpense
    case income
    case refund

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plantPurchase: return "植物采购"
        case .toolPurchase: return "工具采购"
        case .medium: return "介质植料"
        case .careSupply: return "养护用品"
        case .equipment: return "设备器材"
        case .otherExpense: return "其他支出"
        case .income: return "收入"
        case .refund: return "退款"
        }
    }

    static func categories(for kind: LedgerKind) -> [LedgerCategory] {
        switch kind {
        case .expense: return [.plantPurchase, .toolPurchase, .medium, .careSupply, .equipment, .otherExpense]
        case .income: return [.income, .otherExpense]
        case .refund: return [.refund, .plantPurchase, .toolPurchase, .medium, .careSupply, .equipment]
        }
    }
}

enum LedgerSourceType: String, Codable {
    case plant
    case tool
    case orderImport
    case manual
}

struct LedgerEntry: Identifiable, Hashable {
    var id: UUID
    var kind: LedgerKind
    var title: String
    var category: LedgerCategory
    var amount: Decimal
    var currency: String
    var occurredAt: Date
    var platform: String?
    var storeName: String?
    var plantID: UUID?
    var toolID: UUID?
    var note: String?
    var sourceType: LedgerSourceType?
    var sourceID: UUID?
    var relatedEntryID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var signedAmount: Decimal {
        switch kind {
        case .expense: return amount
        case .income: return 0
        case .refund: return relatedEntryID != nil ? -amount : 0
        }
    }
}

struct LedgerDraft: Equatable {
    var kind: LedgerKind = .expense
    var title: String = ""
    var category: LedgerCategory = .plantPurchase
    var amountText: String = ""
    var occurredAt: Date = Date()
    var platform: String = ""
    var storeName: String = ""
    var plantID: UUID?
    var toolID: UUID?
    var relatedEntryID: UUID?
    var note: String = ""
    var generateLedger: Bool = true

    var amount: Decimal? { FivoMoney.parse(amountText) }
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum LedgerFieldError: Equatable {
    case titleRequired
    case amountInvalid
    case refundNeedsSource

    var message: String {
        switch self {
        case .titleRequired: return "请填写账目标题"
        case .amountInvalid: return "金额需为大于 0 且不超过两位小数的数字"
        case .refundNeedsSource: return "退款需要关联原支出账目，才能冲减投入"
        }
    }
}

enum LedgerValidator {
    static func validate(_ draft: LedgerDraft, now: Date) -> [LedgerFieldError] {
        var errors: [LedgerFieldError] = []
        if draft.trimmedTitle.isEmpty { errors.append(.titleRequired) }
        guard let amount = draft.amount, amount > 0 else {
            errors.append(.amountInvalid)
            return errors
        }
        if amount != FivoMoney.round2(amount) {
            errors.append(.amountInvalid)
        }
        if draft.kind == .refund && draft.relatedEntryID == nil {
            errors.append(.refundNeedsSource)
        }
        return errors
    }
}

enum LedgerPeriod: Equatable {
    case all
    case month(Date)
    case year(Int)

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            return true
        case .month(let anchor):
            return calendar.component(.year, from: date) == calendar.component(.year, from: anchor)
                && calendar.component(.month, from: date) == calendar.component(.month, from: anchor)
        case .year(let year):
            return calendar.component(.year, from: date) == year
        }
    }

    var title: String {
        switch self {
        case .all: return "全部"
        case .month(let date): return FivoDate.yearMonthFormatter.string(from: date)
        case .year(let year): return "\(year) 年"
        }
    }
}

struct LedgerSummary: Equatable {
    var totalInvestment: Decimal = 0
    var plantInvestment: Decimal = 0
    var toolInvestment: Decimal = 0
    var otherInvestment: Decimal = 0
    var totalIncome: Decimal = 0
    var totalRefund: Decimal = 0
    var periodExpense: Decimal = 0
    var categoryTotals: [LedgerCategory: Decimal] = [:]
    var monthlyTrend: [YearlySpendPoint] = []
}

struct YearlySpendPoint: Identifiable, Hashable {
    var month: Int
    var amount: Decimal

    var id: Int { month }
}

enum LedgerCalculator {
    static func summary(
        entries: [LedgerEntry],
        period: LedgerPeriod,
        now: Date,
        calendar: Calendar
    ) -> LedgerSummary {
        var summary = LedgerSummary()
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        func bucket(for entry: LedgerEntry) -> LedgerCategory {
            if entry.kind == .refund, let related = entry.relatedEntryID, let source = byID[related] {
                return source.category
            }
            return entry.category
        }

        for entry in entries {
            let inPeriod = period.contains(entry.occurredAt, calendar: calendar)
            switch entry.kind {
            case .expense:
                summary.totalInvestment += entry.amount
                if entry.plantID != nil {
                    summary.plantInvestment += entry.amount
                } else if entry.toolID != nil {
                    summary.toolInvestment += entry.amount
                } else {
                    summary.otherInvestment += entry.amount
                }
                summary.categoryTotals[bucket(for: entry), default: 0] += entry.amount
                if inPeriod {
                    summary.periodExpense += entry.amount
                    let month = calendar.component(.month, from: entry.occurredAt)
                    if let index = summary.monthlyTrend.firstIndex(where: { $0.month == month }) {
                        summary.monthlyTrend[index].amount += entry.amount
                    } else {
                        summary.monthlyTrend.append(YearlySpendPoint(month: month, amount: entry.amount))
                    }
                }
            case .refund:
                guard let relatedID = entry.relatedEntryID, let source = byID[relatedID] else { continue }
                summary.totalRefund += entry.amount
                summary.totalInvestment -= entry.amount
                if source.plantID != nil {
                    summary.plantInvestment -= entry.amount
                } else if source.toolID != nil {
                    summary.toolInvestment -= entry.amount
                } else {
                    summary.otherInvestment -= entry.amount
                }
                summary.categoryTotals[source.category, default: 0] -= entry.amount
                if inPeriod {
                    summary.periodExpense -= entry.amount
                    let month = calendar.component(.month, from: entry.occurredAt)
                    if let index = summary.monthlyTrend.firstIndex(where: { $0.month == month }) {
                        summary.monthlyTrend[index].amount -= entry.amount
                    } else {
                        summary.monthlyTrend.append(YearlySpendPoint(month: month, amount: -entry.amount))
                    }
                }
            case .income:
                summary.totalIncome += entry.amount
            }
        }
        summary.monthlyTrend.sort { $0.month < $1.month }
        return summary
    }

    static func formatted(_ value: Decimal) -> String {
        FivoMoney.display(value)
    }
}
