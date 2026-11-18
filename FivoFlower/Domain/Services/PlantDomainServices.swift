import Foundation

// MARK: - Classification

struct PlantClassificationService {
    var calendar: Calendar = FivoDate.defaultCalendar

    func category(for plant: Plant, now: Date) -> PlantCategory {
        switch plant.lifeStatus {
        case .dead: return .dead
        case .gifted: return .gifted
        case .active:
            guard let acquiredAt = plant.acquiredAt else { return .unclassified }
            guard !FivoDate.isFutureDay(acquiredAt, now: now, calendar: calendar) else {
                return .unclassified
            }
            let years = FivoDate.anniversaryYears(from: acquiredAt, to: now, calendar: calendar)
            if years < 1 { return .activeUnderOneYear }
            if years < 2 { return .activeOneToTwoYears }
            return .activeOverTwoYears
        }
    }

    func counts(for plants: [Plant], now: Date) -> [PlantCategory: Int] {
        var result: [PlantCategory: Int] = [:]
        for plant in plants {
            result[category(for: plant, now: now), default: 0] += 1
        }
        return result
    }

    func matches(_ plant: Plant, category: PlantCategory, now: Date) -> Bool {
        self.category(for: plant, now: now) == category
    }
}

// MARK: - Duration

struct PlantDurationCalculator {
    var calendar: Calendar = FivoDate.defaultCalendar

    /// 已陪伴天数：购买日至今天（或归档日），开始当天计为第 1 天。
    func companionDays(for plant: Plant, now: Date) -> Int? {
        guard let acquiredAt = plant.acquiredAt else { return nil }
        guard !FivoDate.isFutureDay(acquiredAt, now: now, calendar: calendar) else { return nil }
        let end: Date
        switch plant.lifeStatus {
        case .active:
            end = now
        case .dead, .gifted:
            end = plant.lifeEventAt ?? now
        }
        guard !FivoDate.isFutureDay(end, now: now, calendar: calendar) else {
            return FivoDate.inclusiveDays(from: acquiredAt, through: now, calendar: calendar)
        }
        return FivoDate.inclusiveDays(from: acquiredAt, through: end, calendar: calendar)
    }

    /// 状态持续天数：进行中计算至今天，已结束计算至结束日；开始当天为第 1 天。
    func stageDays(startedAt: Date, endedAt: Date?, now: Date) -> Int? {
        guard !FivoDate.isFutureDay(startedAt, now: now, calendar: calendar) else { return nil }
        if let endedAt, endedAt < startedAt {
            return nil
        }
        let end = endedAt ?? now
        let clampedEnd = min(end, now)
        return FivoDate.inclusiveDays(from: startedAt, through: clampedEnd, calendar: calendar)
    }

    func bloomDuration(session: GrowthSession, now: Date) -> Int? {
        stageDays(startedAt: session.startedAt, endedAt: session.endedAt, now: now)
    }
}

// MARK: - Statistics

struct PlantStatisticsService {
    var calendar: Calendar = FivoDate.defaultCalendar
    var durationCalculator: PlantDurationCalculator { PlantDurationCalculator(calendar: calendar) }

    func statistics(sessions: [GrowthSession], now: Date) -> PlantStatistics {
        var stats = PlantStatistics()
        let valid = sessions.filter {
            !FivoDate.isFutureDay($0.startedAt, now: now, calendar: calendar)
        }

        let spikes = valid
            .filter { $0.stageKey == GrowthStageKey.flowerSpike }
            .sorted { $0.startedAt < $1.startedAt }
        stats.spikeCount = spikes.count
        stats.mostRecentSpikeAt = spikes.last?.startedAt
        if spikes.count >= 2 {
            var intervals: [Int] = []
            for index in 1..<spikes.count {
                let diff = FivoDate.dayDifference(
                    from: spikes[index - 1].startedAt,
                    to: spikes[index].startedAt,
                    calendar: calendar
                )
                if diff >= 0 { intervals.append(diff) }
            }
            if !intervals.isEmpty {
                stats.averageSpikeIntervalDays = Double(intervals.reduce(0, +)) / Double(intervals.count)
            }
        }

        let blooms = valid
            .filter { $0.stageKey == GrowthStageKey.bloom }
            .sorted { $0.startedAt < $1.startedAt }
        stats.bloomCount = blooms.count
        stats.mostRecentBloomAt = blooms.last?.startedAt

        var completedDurations: [Int] = []
        for bloom in blooms {
            guard let days = durationCalculator.stageDays(
                startedAt: bloom.startedAt,
                endedAt: bloom.endedAt,
                now: now
            ) else { continue }
            if bloom.endedAt != nil {
                completedDurations.append(days)
            } else {
                stats.ongoingBloomDurationDays = days
            }
        }
        if !completedDurations.isEmpty {
            stats.averageBloomDurationDays = Double(completedDurations.reduce(0, +)) / Double(completedDurations.count)
            stats.longestBloomDurationDays = completedDurations.max()
        }
        return stats
    }

    func yearlyTrend(
        sessions: [GrowthSession],
        year: Int,
        now: Date
    ) -> [YearlyGrowthPoint] {
        var points = (0..<12).map { YearlyGrowthPoint(month: $0 + 1, spikeCount: 0, bloomCount: 0) }
        for session in sessions {
            guard !FivoDate.isFutureDay(session.startedAt, now: now, calendar: calendar) else { continue }
            guard calendar.component(.year, from: session.startedAt) == year else { continue }
            let month = calendar.component(.month, from: session.startedAt)
            guard month >= 1, month <= 12 else { continue }
            switch session.stageKey {
            case GrowthStageKey.flowerSpike:
                points[month - 1].spikeCount += 1
            case GrowthStageKey.bloom:
                points[month - 1].bloomCount += 1
            default:
                break
            }
        }
        return points
    }
}

// MARK: - Order parsing

struct LocalOrderParser {
    var calendar: Calendar = FivoDate.defaultCalendar

    func parse(ocrText: String, now: Date) -> OrderDraft {
        var draft = OrderDraft()
        draft.rawOCRText = ocrText
        let text = Self.normalized(ocrText)

        if let amount = Self.parseAmount(in: text) {
            draft.amountText = amount
        } else {
            draft.lowConfidenceFields.insert(.amount)
        }

        if let date = Self.parseDate(in: text, calendar: calendar),
           !FivoDate.isFutureDay(date, now: now, calendar: calendar) {
            draft.acquiredAt = date
        } else {
            draft.lowConfidenceFields.insert(.purchaseDate)
        }

        if let platform = Self.parsePlatform(in: text) {
            draft.platform = platform
        } else {
            draft.lowConfidenceFields.insert(.platform)
        }

        if let store = Self.parseStoreName(in: text) {
            draft.storeName = store
        } else {
            draft.lowConfidenceFields.insert(.storeName)
        }

        if let orderNumber = Self.parseOrderNumber(in: text) {
            draft.orderNumber = orderNumber
        } else {
            draft.lowConfidenceFields.insert(.orderNumber)
        }

        draft.plantName = Self.parseProductName(in: text)
        if draft.plantName.isEmpty {
            draft.lowConfidenceFields.insert(.plantName)
        }

        if let spec = Self.firstMatch(
            patterns: [
                "(?:规格|尺寸|型号|颜色分类|花色|苗情)[:：]\\s*([^\\n]{1,30})"
            ],
            in: text
        ) {
            draft.specification = spec.trimmingCharacters(in: .whitespaces)
        } else {
            draft.lowConfidenceFields.insert(.specification)
        }

        draft.createLedgerEntry = true
        return draft
    }

    // MARK: - Amount

    /// 成交金额优先：实付/成交价/到手价 > 应付/支付/订单金额 > 合计/总价。
    /// 商品原价、单价、划线价只作为最后兜底，且尽量排除。
    static func parseAmount(in text: String) -> String? {
        let labels = [
            "实际成交价", "成交金额", "成交价", "实付款", "实付金额", "实付",
            "实际付款", "实际支付", "应付金额", "应付", "付款金额", "支付金额",
            "支付价格", "订单金额", "到手价", "实收", "合计", "总计", "总价"
        ]
        for label in labels {
            if let value = firstMatch(
                patterns: ["\(label)[^0-9]{0,16}([0-9]+(?:\\.[0-9]{1,2})?)"],
                in: text
            ), isValidAmount(value) {
                return value
            }
        }

        // 兜底：扫描带货币符号/“元”的金额，排除明显属于原价或商品标价的行
        let excludedMarkers = ["原价", "商品价格", "商品金额", "单价", "市场价", "划线价", "优惠前", "吊牌价", "参考价"]
        var candidates: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if excludedMarkers.contains(where: { line.contains($0) }) { continue }
            candidates += allMatches(
                patterns: [
                    "[¥￥]\\s*([0-9]+(?:\\.[0-9]{1,2})?)",
                    "([0-9]+(?:\\.[0-9]{1,2})?)\\s*元"
                ],
                in: line
            )
        }
        return candidates.last(where: isValidAmount)
    }

    static func isValidAmount(_ value: String) -> Bool {
        guard let amount = Decimal(string: value), amount > 0 else { return false }
        return amount == FivoMoney.round2(amount)
    }

    // MARK: - Platform

    static func parsePlatform(in text: String) -> String? {
        let platforms: [(String, [String])] = [
            ("淘宝", ["淘宝", "taobao", "tmall", "天猫"]),
            ("闲鱼", ["闲鱼", "goofish", "xianyu"]),
            ("拼多多", ["拼多多", "pinduoduo", "多多买菜"]),
            ("京东", ["京东", "jd.com"]),
            ("抖音", ["抖音", "douyin", "抖店", "抖音商城"]),
            ("小红书", ["小红书", "xiaohongshu", "薯店"]),
            ("微店", ["微店", "weidian"]),
            ("转转", ["转转", "zhuanzhuan"]),
            ("得物", ["得物", "poizon"])
        ]
        for (name, keywords) in platforms {
            if keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                return name
            }
        }
        return nil
    }

    // MARK: - Store

    static func parseStoreName(in text: String) -> String? {
        let patterns = [
            "(?:店铺名称|店铺|商家名称|商家|卖家昵称|卖家名称|卖家|店主|掌柜|昵称)[:：]?\\s*([^\\n]{1,30})",
            "来自\\s*([^\\n]{1,20})\\s*的(?:闲鱼|店铺)",
            "([^\\s\\n]{2,20}(?:旗舰店|官方店|花艺|植物园|工作室|花店|园艺|绿植店|园艺店))"
        ]
        let noise = ["保障", "信用", "服务", "发货", "包邮", "评价", "粉丝", "关注", "已售", "退款", "客服", "优惠"]
        for pattern in patterns {
            for candidate in allMatches(patterns: [pattern], in: text) {
                var cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if let cutoff = noise.compactMap({ cleaned.range(of: $0)?.lowerBound }).min() {
                    cleaned = String(cleaned[..<cutoff])
                }
                cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "：:·-—")))
                if cleaned.count >= 2, cleaned.count <= 24 {
                    return cleaned
                }
            }
        }
        return nil
    }

    // MARK: - Order number

    static func parseOrderNumber(in text: String) -> String? {
        firstMatch(
            patterns: [
                "(?:订单号|订单编号|交易订单号|交易号)[:：]?\\s*([A-Za-z0-9\\-]{6,})",
                "\\b([0-9]{15,24})\\b"
            ],
            in: text
        )
    }

    // MARK: - Product name

    static func parseProductName(in text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let metadataMarkers = [
            "订单", "实付", "付款", "支付", "金额", "价格", "原价", "优惠", "运费", "快递",
            "发货", "收货", "评价", "客服", "退款", "售后", "规格", "尺寸", "型号", "数量",
            "库存", "店铺", "商家", "卖家", "掌柜", "包邮", "已拼", "已售", "月销", "编号",
            "单价", "合计", "总计", "小计", "件数"
        ]
        let plantKeywords = [
            "兰", "花", "植物", "绿植", "盆栽", "苗", "多肉", "蕨", "龟背竹", "蔓绿绒",
            "海芋", "花烛", "秋海棠", "竹芋", "榕", "芋", "球兰", "石斛", "绣球", "月季",
            "玫瑰", "茉莉", "栀子", "薄荷", "苔藓", "凤梨", "食虫", "捕蝇草", "猪笼草",
            "沙漠玫瑰", "朱顶红", "风信子", "郁金香", "百合", "鸢尾", "芍药", "牡丹",
            "铁线莲", "三角梅", "天南星", "合果芋", "绿萝", "常春藤", "虎尾兰", "龙舌兰",
            "芦荟", "仙人掌", "量天尺", "十二卷", "生石花", "蜡质"
        ]

        var best: (line: String, score: Int)?
        for line in lines {
            var score = min(line.count, 30)
            if plantKeywords.contains(where: { line.contains($0) }) { score += 60 }
            if metadataMarkers.contains(where: { line.contains($0) }) { score -= 45 }
            let digitCount = line.filter { $0.isNumber }.count
            if digitCount > 0, Double(digitCount) / Double(max(1, line.count)) > 0.3 {
                score -= 30
            }
            if !line.contains(where: { isChinese($0) }) { score -= 40 }
            if line.count <= 3 { score -= 15 }
            if line.contains("¥") || line.contains("￥") { score -= 20 }
            if score > (best?.score ?? Int.min) {
                best = (line, score)
            }
        }
        guard let best else { return "" }
        return cleanProductName(best.line)
    }

    static func cleanProductName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for token in ["【", "】", "「", "」", "[", "]"] {
            name = name.replacingOccurrences(of: token, with: "")
        }

        // 营销标题通常以逗号/竖线分隔，第一段才是品种名
        let separators = ["，", ",", "|", "｜", "；", ";", "·"]
        var segments = [name]
        for separator in separators {
            segments = segments.flatMap { $0.components(separatedBy: separator) }
        }
        if let first = segments.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            name = first.trimmingCharacters(in: .whitespaces)
        }

        let markers = [
            "包邮", "现货", "预售", "一物一拍", "带盆", "不含盆", "裸根", "苗情",
            "规格", "尺寸", "颜色分类", "随机发货", "多规格", "特价", "秒杀", "新品", "爆款"
        ]
        var cut = name.endIndex
        for marker in markers {
            if let range = name.range(of: marker), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        // 去掉 2.8寸 / 14cm / 12厘米 / 1加仑 等规格片段
        if let regex = try? NSRegularExpression(
            pattern: "[0-9]+(?:\\.[0-9]+)?\\s*(?:cm|CM|厘米|寸|mm|MM|加仑|号盆)"
        ) {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if let match = regex.firstMatch(in: name, options: [], range: range),
               let swiftRange = Range(match.range, in: name),
               swiftRange.lowerBound < cut {
                cut = swiftRange.lowerBound
            }
        }
        name = String(name[..<cut])

        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "-_—·:：,，.。、"))
        name = name.trimmingCharacters(in: trimSet)
        return name
    }

    // MARK: - Shared helpers

    static func normalized(_ text: String) -> String {
        let fullWidthDigits: [Character: Character] = [
            "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
            "５": "5", "６": "6", "７": "7", "８": "8", "９": "9", "．": "."
        ]
        let mapped = String(text.map { fullWidthDigits[$0] ?? $0 })
        return mapped.replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    static func allMatches(patterns: [String], in text: String) -> [String] {
        var result: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, options: [], range: range) {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let swiftRange = Range(captureRange, in: text) {
                    let value = String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { result.append(value) }
                }
            }
        }
        return result
    }

    static func firstMatch(patterns: [String], in text: String) -> String? {
        allMatches(patterns: patterns, in: text).first
    }

    static func parseDate(in text: String, calendar: Calendar) -> Date? {
        let patterns = [
            "([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})日?",
            "([0-9]{4})\\.([0-9]{1,2})\\.([0-9]{1,2})"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 4,
               let yearRange = Range(match.range(at: 1), in: text),
               let monthRange = Range(match.range(at: 2), in: text),
               let dayRange = Range(match.range(at: 3), in: text),
               let year = Int(text[yearRange]),
               let month = Int(text[monthRange]),
               let day = Int(text[dayRange]) {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                if let date = calendar.date(from: components) {
                    return date
                }
            }
        }
        return nil
    }
}
