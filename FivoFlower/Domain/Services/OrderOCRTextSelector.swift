import Foundation

struct OrderOCRSelection: Equatable {
    var text: String
    var includedIndices: [Int]
    var ignoredCount: Int
}

/// 多张截图 OCR 结果筛选：只把“像订单”的文本块交给订单解析，
/// 避免把误选的 App 截图（花房/详情页）文本混入品种名、平台等字段。
struct OrderOCRTextSelector {
    var calendar: Calendar = FivoDate.defaultCalendar
    var now: Date = Date()

    private static let appMarkers = [
        "已陪伴", "当前生长状态", "切换状态", "查看状态历史", "记养护", "写日志",
        "加照片", "花房", "档案日志", "花园账本", "养叶养根",
        "出花梗 · 第", "出花梗·第", "开花 · 第", "开花·第", "我的花房",
        "植物详情", "概览", "统计", "养护日历", "设置", "新增", "版本", "Fivo的花花"
    ]

    private static let orderMarkers = [
        "订单", "实付", "实付款", "付款", "支付", "成交价", "金额", "合计", "总计",
        "小计", "商品", "宝贝", "物流", "发货", "收货", "退款", "运费", "优惠", "元"
    ]

    private static let platformMarkers = [
        "闲鱼", "淘宝", "天猫", "拼多多", "京东", "抖音", "小红书", "微店", "转转",
        "得物", "goofish", "taobao", "tmall", "pinduoduo", "jd.com", "douyin"
    ]

    func select(from texts: [String]) -> OrderOCRSelection {
        let scored: [(index: Int, text: String, score: Int)] = texts.enumerated().compactMap { index, text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return (index, trimmed, score(trimmed))
        }
        guard !scored.isEmpty else {
            return OrderOCRSelection(text: "", includedIndices: [], ignoredCount: texts.count)
        }

        var chosen = scored.filter { $0.score >= 20 }
        if chosen.isEmpty {
            let nonApp = scored.filter { item in
                !Self.appMarkers.contains(where: { item.text.contains($0) })
            }
            if let best = nonApp.max(by: { $0.score < $1.score }) {
                chosen = [best]
            } else {
                // 所有文本都像 App 页面，说明选错了截图，不能拿来做订单解析
                return OrderOCRSelection(text: "", includedIndices: [], ignoredCount: texts.count)
            }
        }
        chosen.sort { $0.index < $1.index }
        let included = Set(chosen.map(\.index))
        let text = chosen.map(\.text).joined(separator: "\n")
        return OrderOCRSelection(
            text: text,
            includedIndices: chosen.map(\.index),
            ignoredCount: texts.count - included.count
        )
    }

    func score(_ text: String) -> Int {
        var score = 0
        if Self.orderMarkers.contains(where: { text.contains($0) }) {
            score += 40
        }
        if text.contains("¥") || text.contains("￥") {
            score += 20
        }
        if Self.platformMarkers.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            score += 20
        }
        if containsDate(text) {
            score += 10
        }
        if Self.appMarkers.contains(where: { text.contains($0) }) {
            score -= 80
        }
        score += min(text.count / 50, 10)
        return score
    }

    private func containsDate(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: "[0-9]{4}\\s*[-/年.]\\s*[0-9]{1,2}\\s*[-/月.]\\s*[0-9]{1,2}"
        ) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
