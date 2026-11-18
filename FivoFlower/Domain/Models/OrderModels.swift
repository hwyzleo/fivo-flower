import Foundation

// MARK: - Order draft

/// 订单截图的本地解析结果。所有字段在确认页均可被用户修正。
struct OrderDraft: Equatable {
    var plantName: String = ""
    var specification: String = ""
    var acquiredAt: Date?
    var amountText: String = ""
    var platform: String = ""
    var storeName: String = ""
    var orderNumber: String = ""
    var sourceURL: String = ""
    var rawOCRText: String = ""
    var createLedgerEntry: Bool = true
    var lowConfidenceFields: Set<OrderDraftField> = []
    var attachmentIDs: [UUID] = []

    var amount: Decimal? { FivoMoney.parse(amountText) }

    var canCreateLedger: Bool {
        createLedgerEntry && (amount ?? 0) > 0
    }
}

enum OrderDraftField: String, CaseIterable, Hashable {
    case plantName
    case purchaseDate
    case amount
    case platform
    case storeName
    case orderNumber
    case specification

    var title: String {
        switch self {
        case .plantName: return "品种名称"
        case .purchaseDate: return "购买日期"
        case .amount: return "支付金额"
        case .platform: return "平台"
        case .storeName: return "店铺"
        case .orderNumber: return "订单号"
        case .specification: return "规格"
        }
    }
}
