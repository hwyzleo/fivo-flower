import XCTest
@testable import FivoFlower

final class DomainRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ string: String, time: String = "12:00") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(string) \(time)")!
    }

    private func makePlant(
        name: String = "测试植物",
        acquiredAt: Date?,
        lifeStatus: PlantLifeStatus = .active,
        lifeEventAt: Date? = nil
    ) -> Plant {
        Plant(
            id: UUID(),
            name: name,
            alias: nil,
            plantCode: nil,
            specification: nil,
            acquiredAt: acquiredAt,
            purchasePrice: nil,
            currency: "CNY",
            platform: nil,
            storeName: nil,
            sourceURL: nil,
            medium: nil,
            location: nil,
            notes: nil,
            lifeStatus: lifeStatus,
            lifeEventAt: lifeEventAt,
            lifeEventReason: nil,
            giftRecipient: nil,
            coverPhotoID: nil,
            createdAt: date("2024-01-01"),
            updatedAt: date("2024-01-01")
        )
    }

    private func makeSession(
        stage: String,
        start: Date,
        end: Date? = nil
    ) -> GrowthSession {
        GrowthSession(
            id: UUID(),
            plantID: UUID(),
            stageKey: stage,
            startedAt: start,
            endedAt: end,
            note: nil,
            createdAt: start,
            updatedAt: start
        )
    }

    private func makeEntry(
        id: UUID = UUID(),
        kind: LedgerKind,
        amount: Decimal,
        category: LedgerCategory = .plantPurchase,
        date: Date,
        plantID: UUID? = nil,
        toolID: UUID? = nil,
        related: UUID? = nil
    ) -> LedgerEntry {
        LedgerEntry(
            id: id,
            kind: kind,
            title: "测试",
            category: category,
            amount: amount,
            currency: "CNY",
            occurredAt: date,
            platform: nil,
            storeName: nil,
            plantID: plantID,
            toolID: toolID,
            note: nil,
            sourceType: .manual,
            sourceID: nil,
            relatedEntryID: related,
            createdAt: date,
            updatedAt: date
        )
    }

    // MARK: - Classification

    func testClassificationFollowsLifeStatusAndAnniversary() {
        let service = PlantClassificationService(calendar: calendar)
        let now = date("2025-06-15")

        XCTAssertEqual(service.category(for: makePlant(acquiredAt: nil), now: now), .unclassified)
        XCTAssertEqual(
            service.category(for: makePlant(acquiredAt: date("2025-06-15")), now: now),
            .activeUnderOneYear
        )
        XCTAssertEqual(
            service.category(for: makePlant(acquiredAt: date("2025-06-16")), now: now),
            .unclassified,
            "未来日期不参与分类"
        )
        XCTAssertEqual(
            service.category(for: makePlant(acquiredAt: date("2024-06-16")), now: now),
            .activeUnderOneYear
        )
        XCTAssertEqual(
            service.category(for: makePlant(acquiredAt: date("2024-06-15")), now: now),
            .activeOneToTwoYears
        )
        XCTAssertEqual(
            service.category(for: makePlant(acquiredAt: date("2023-06-15")), now: now),
            .activeOverTwoYears
        )
        XCTAssertEqual(
            service.category(
                for: makePlant(acquiredAt: date("2020-01-01"), lifeStatus: .dead, lifeEventAt: date("2025-01-01")),
                now: now
            ),
            .dead
        )
        XCTAssertEqual(
            service.category(
                for: makePlant(acquiredAt: date("2020-01-01"), lifeStatus: .gifted, lifeEventAt: date("2025-01-01")),
                now: now
            ),
            .gifted
        )
    }

    func testLeapDayAnniversary() {
        let service = PlantClassificationService(calendar: calendar)
        let leap = makePlant(acquiredAt: date("2024-02-29"))
        XCTAssertEqual(service.category(for: leap, now: date("2025-02-27")), .activeUnderOneYear)
        XCTAssertEqual(service.category(for: leap, now: date("2025-02-28")), .activeOneToTwoYears)
        XCTAssertEqual(service.category(for: leap, now: date("2026-02-28")), .activeOverTwoYears)
    }

    func testCategoryCounts() {
        let service = PlantClassificationService(calendar: calendar)
        let now = date("2025-06-15")
        let plants = [
            makePlant(acquiredAt: date("2025-01-01")),
            makePlant(acquiredAt: date("2024-06-15")),
            makePlant(acquiredAt: nil),
            makePlant(acquiredAt: date("2022-01-01"), lifeStatus: .dead, lifeEventAt: date("2023-01-01"))
        ]
        let counts = service.counts(for: plants, now: now)
        XCTAssertEqual(counts[.activeUnderOneYear], 1)
        XCTAssertEqual(counts[.activeOneToTwoYears], 1)
        XCTAssertEqual(counts[.unclassified], 1)
        XCTAssertEqual(counts[.dead], 1)
        XCTAssertNil(counts[.gifted])
    }

    // MARK: - Duration

    func testInclusiveDays() {
        XCTAssertEqual(FivoDate.inclusiveDays(from: date("2025-01-01"), through: date("2025-01-01"), calendar: calendar), 1)
        XCTAssertEqual(FivoDate.inclusiveDays(from: date("2025-01-01"), through: date("2025-01-31"), calendar: calendar), 31)
        XCTAssertEqual(FivoDate.inclusiveDays(from: date("2024-12-31"), through: date("2025-01-01"), calendar: calendar), 2)
    }

    func testCompanionDays() {
        let calculator = PlantDurationCalculator(calendar: calendar)
        let now = date("2025-06-15")
        XCTAssertEqual(calculator.companionDays(for: makePlant(acquiredAt: date("2025-06-15")), now: now), 1)
        XCTAssertEqual(calculator.companionDays(for: makePlant(acquiredAt: date("2025-06-01")), now: now), 15)
        XCTAssertEqual(
            calculator.companionDays(
                for: makePlant(acquiredAt: date("2025-05-01"), lifeStatus: .dead, lifeEventAt: date("2025-05-10")),
                now: now
            ),
            10
        )
        XCTAssertNil(calculator.companionDays(for: makePlant(acquiredAt: nil), now: now))
        XCTAssertNil(calculator.companionDays(for: makePlant(acquiredAt: date("2025-07-01")), now: now))
    }

    func testStageDays() {
        let calculator = PlantDurationCalculator(calendar: calendar)
        let now = date("2025-06-15")
        XCTAssertEqual(
            calculator.stageDays(startedAt: date("2025-06-15", time: "08:00"), endedAt: nil, now: now),
            1
        )
        XCTAssertEqual(
            calculator.stageDays(startedAt: date("2025-06-01"), endedAt: date("2025-06-10"), now: now),
            10
        )
        XCTAssertNil(calculator.stageDays(startedAt: date("2025-06-20"), endedAt: nil, now: now))
        XCTAssertNil(calculator.stageDays(startedAt: date("2025-06-10"), endedAt: date("2025-06-01"), now: now))
    }

    // MARK: - Statistics

    func testSpikeIntervalsAndBloomDurations() {
        let service = PlantStatisticsService(calendar: calendar)
        let now = date("2025-06-15")
        let sessions = [
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-01-01")),
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-01-11")),
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-01-31")),
            makeSession(stage: GrowthStageKey.bloom, start: date("2025-01-01"), end: date("2025-01-10")),
            makeSession(stage: GrowthStageKey.bloom, start: date("2025-01-20"), end: date("2025-01-25")),
            makeSession(stage: GrowthStageKey.bloom, start: date("2025-02-01"))
        ]
        let stats = service.statistics(sessions: sessions, now: now)
        XCTAssertEqual(stats.spikeCount, 3)
        XCTAssertEqual(stats.averageSpikeIntervalDays ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(stats.mostRecentSpikeAt, date("2025-01-31"))
        XCTAssertEqual(stats.bloomCount, 3)
        XCTAssertEqual(stats.averageBloomDurationDays ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(stats.longestBloomDurationDays, 10)
        XCTAssertEqual(stats.mostRecentBloomAt, date("2025-02-01"))
        let ongoing = PlantDurationCalculator(calendar: calendar)
            .stageDays(startedAt: date("2025-02-01"), endedAt: nil, now: now)
        XCTAssertEqual(stats.ongoingBloomDurationDays, ongoing)
    }

    func testInsufficientStatisticsDoNotShowZero() {
        let service = PlantStatisticsService(calendar: calendar)
        let stats = service.statistics(
            sessions: [makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-01-01"))],
            now: date("2025-06-15")
        )
        XCTAssertEqual(stats.spikeCount, 1)
        XCTAssertNil(stats.averageSpikeIntervalDays)
        XCTAssertNil(stats.averageBloomDurationDays)
    }

    func testFutureSessionsExcluded() {
        let service = PlantStatisticsService(calendar: calendar)
        let now = date("2025-06-15")
        let stats = service.statistics(
            sessions: [
                makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-06-20")),
                makeSession(stage: GrowthStageKey.bloom, start: date("2025-06-16"))
            ],
            now: now
        )
        XCTAssertEqual(stats.spikeCount, 0)
        XCTAssertEqual(stats.bloomCount, 0)
    }

    func testYearlyTrend() {
        let service = PlantStatisticsService(calendar: calendar)
        let sessions = [
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-03-01")),
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2025-03-20")),
            makeSession(stage: GrowthStageKey.bloom, start: date("2025-04-01")),
            makeSession(stage: GrowthStageKey.flowerSpike, start: date("2024-03-01"))
        ]
        let trend = service.yearlyTrend(sessions: sessions, year: 2025, now: date("2025-06-15"))
        XCTAssertEqual(trend.count, 12)
        XCTAssertEqual(trend[2].spikeCount, 2)
        XCTAssertEqual(trend[3].bloomCount, 1)
    }

    // MARK: - Money & validation

    func testMoneyParsingAndRounding() {
        XCTAssertEqual(FivoMoney.parse("¥1,234.50"), Decimal(string: "1234.5"))
        XCTAssertEqual(FivoMoney.parse("420"), 420)
        XCTAssertEqual(FivoMoney.parse("0"), 0)
        XCTAssertNil(FivoMoney.parse("-1"))
        XCTAssertNil(FivoMoney.parse("1.234"))
        XCTAssertNil(FivoMoney.parse("abc"))
        XCTAssertEqual(FivoMoney.plainString(120.5), "120.5")
        XCTAssertEqual(FivoMoney.round2(Decimal(string: "1.005")!), Decimal(string: "1.01"))
        XCTAssertTrue(FivoMoney.display(420).contains("420.00"))
    }

    func testPlantValidation() {
        var draft = PlantDraft()
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.nameRequired))

        draft.name = "  "
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.nameRequired))

        draft.name = "月季"
        draft.purchasePriceText = "-2"
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.priceInvalid))

        draft.purchasePriceText = "12.345"
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.priceInvalid))

        draft.purchasePriceText = "12.35"
        XCTAssertFalse(PlantValidator.validate(draft, now: Date()).contains(.priceInvalid))

        draft.sourceURL = "not-a-url"
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.urlInvalid))
        draft.sourceURL = "https://example.com/item"
        XCTAssertFalse(PlantValidator.validate(draft, now: Date()).contains(.urlInvalid))

        draft.acquiredAt = Date().addingTimeInterval(86_400 * 3)
        XCTAssertTrue(PlantValidator.validate(draft, now: Date()).contains(.dateInFuture))
    }

    func testLifeEventValidation() {
        let plant = makePlant(acquiredAt: date("2024-01-01"))
        var draft = LifeEventDraft(status: .dead, date: date("2025-01-01"))
        XCTAssertTrue(LifeEventValidator.errors(draft: draft, plant: plant, now: date("2025-06-15")).isEmpty)
        draft.date = date("2023-01-01")
        XCTAssertFalse(LifeEventValidator.errors(draft: draft, plant: plant, now: date("2025-06-15")).isEmpty)
        draft.date = date("2025-07-01")
        XCTAssertFalse(LifeEventValidator.errors(draft: draft, plant: plant, now: date("2025-06-15")).isEmpty)
    }

    func testLedgerValidation() {
        var draft = LedgerDraft()
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).contains(.titleRequired))
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).contains(.amountInvalid))

        draft.title = "采购"
        draft.amountText = "0"
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).contains(.amountInvalid))

        draft.amountText = "12.345"
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).contains(.amountInvalid))

        draft.amountText = "12.34"
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).isEmpty)

        draft.kind = .refund
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).contains(.refundNeedsSource))
        draft.relatedEntryID = UUID()
        XCTAssertTrue(LedgerValidator.validate(draft, now: Date()).isEmpty)
    }

    // MARK: - Ledger math

    func testLedgerInvestmentIgnoresIncomeAndUnlinkedRefund() {
        let plantID = UUID()
        let toolID = UUID()
        let plantExpenseID = UUID()
        let entries = [
            makeEntry(id: plantExpenseID, kind: .expense, amount: 100, date: date("2025-01-10"), plantID: plantID),
            makeEntry(kind: .expense, amount: 50, category: .toolPurchase, date: date("2025-01-11"), toolID: toolID),
            makeEntry(kind: .expense, amount: 20, category: .otherExpense, date: date("2025-01-12")),
            makeEntry(kind: .income, amount: 500, category: .income, date: date("2025-01-13")),
            makeEntry(
                kind: .refund,
                amount: 30,
                category: .plantPurchase,
                date: date("2025-01-14"),
                related: plantExpenseID
            ),
            makeEntry(kind: .refund, amount: 99, category: .plantPurchase, date: date("2025-01-15"))
        ]
        let summary = LedgerCalculator.summary(
            entries: entries,
            period: .all,
            now: date("2025-06-15"),
            calendar: calendar
        )
        XCTAssertEqual(summary.totalInvestment, 140)
        XCTAssertEqual(summary.plantInvestment, 70)
        XCTAssertEqual(summary.toolInvestment, 50)
        XCTAssertEqual(summary.otherInvestment, 20)
        XCTAssertEqual(summary.totalIncome, 500)
        XCTAssertEqual(summary.totalRefund, 30)
        XCTAssertEqual(summary.categoryTotals[.plantPurchase], 70)
    }

    func testLedgerPeriodAndMonthlyTrend() {
        let entries = [
            makeEntry(kind: .expense, amount: 10, date: date("2025-01-11")),
            makeEntry(kind: .expense, amount: 20, date: date("2025-01-20")),
            makeEntry(kind: .expense, amount: 30, date: date("2025-02-01")),
            makeEntry(kind: .expense, amount: 40, date: date("2024-12-31"))
        ]
        let january = LedgerCalculator.summary(
            entries: entries,
            period: .month(date("2025-01-15")),
            now: date("2025-06-15"),
            calendar: calendar
        )
        XCTAssertEqual(january.periodExpense, 30)
        XCTAssertEqual(january.totalInvestment, 100)
        let janTrend = january.monthlyTrend.first(where: { $0.month == 1 })
        XCTAssertEqual(janTrend?.amount, 30)

        let year = LedgerCalculator.summary(
            entries: entries,
            period: .year(2025),
            now: date("2025-06-15"),
            calendar: calendar
        )
        XCTAssertEqual(year.periodExpense, 60)
        XCTAssertEqual(year.monthlyTrend.count, 2)
    }

    // MARK: - Stock

    func testStockCalculator() throws {
        XCTAssertEqual(try StockCalculator.resultingStock(current: 5, mode: .increase, amount: 2), 7)
        XCTAssertEqual(try StockCalculator.resultingStock(current: 5, mode: .decrease, amount: 5), 0)
        XCTAssertEqual(try StockCalculator.resultingStock(current: 5, mode: .calibrate, amount: 9), 9)
        XCTAssertThrowsError(try StockCalculator.resultingStock(current: 2, mode: .decrease, amount: 3)) { error in
            XCTAssertEqual(error as? StockError, .insufficientStock)
        }
        XCTAssertThrowsError(try StockCalculator.resultingStock(current: 2, mode: .increase, amount: -1))
    }

    func testToolValidationAndLowStock() {
        var draft = ToolDraft()
        XCTAssertTrue(ToolValidator.validate(draft).contains(.nameRequired))
        draft.name = "水苔"
        draft.purchasePriceText = "12.345"
        XCTAssertTrue(ToolValidator.validate(draft).contains(.priceInvalid))
        draft.purchasePriceText = "12.34"
        XCTAssertTrue(ToolValidator.validate(draft).isEmpty)

        let tool = ToolItem(
            id: UUID(),
            name: "水苔",
            category: .medium,
            brand: nil,
            specification: nil,
            purchasedAt: nil,
            purchasePrice: 12.34,
            quantity: 1,
            location: nil,
            photoRelativePath: nil,
            notes: nil,
            isConsumable: true,
            stock: 1,
            stockUnit: "包",
            lowStockThreshold: 2,
            lowStockEnabled: true,
            isDevice: false,
            isPoweredOn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertTrue(tool.isLowStock)
    }

    // MARK: - Reminder recurrence

    func testReminderRecurrence() {
        let base = date("2025-06-15")
        XCTAssertEqual(ReminderRecurrence.everyNDays(3).nextDue(after: base, calendar: calendar), date("2025-06-18"))
        XCTAssertEqual(ReminderRecurrence.everyNWeeks(2).nextDue(after: base, calendar: calendar), date("2025-06-29"))
        XCTAssertEqual(ReminderRecurrence.everyNMonths(1).nextDue(after: base, calendar: calendar), date("2025-07-15"))
        XCTAssertEqual(ReminderRecurrence.everyNYears(1).nextDue(after: base, calendar: calendar), date("2026-06-15"))
        XCTAssertEqual(
            ReminderRecurrence.everyNMonths(1).nextDue(after: date("2025-01-31", time: "09:30"), calendar: calendar),
            date("2025-02-28", time: "09:30"),
            "目标月没有同日时取月末并保留时间"
        )
        XCTAssertEqual(
            ReminderRecurrence.everyNYears(1).nextDue(after: date("2024-02-29"), calendar: calendar),
            date("2025-02-28")
        )

        XCTAssertEqual(ReminderRecurrence(rawValue: "every:5"), .everyNDays(5))
        XCTAssertEqual(ReminderRecurrence(rawValue: "weeks:2"), .everyNWeeks(2))
        XCTAssertEqual(ReminderRecurrence(rawValue: "months:3"), .everyNMonths(3))
        XCTAssertEqual(ReminderRecurrence(rawValue: "years:4"), .everyNYears(4))
        XCTAssertNil(ReminderRecurrence(rawValue: "once"))
        XCTAssertNil(ReminderRecurrence(rawValue: "weekly:1,3"))
        XCTAssertNil(ReminderRecurrence(rawValue: "every:0"))
        XCTAssertNil(ReminderRecurrence(rawValue: "unknown"))

        let bucketSource = [
            CareReminder(
                id: UUID(), plantID: UUID(), actionTypeID: nil, actionNameSnapshot: nil,
                title: "浇水", dueAt: date("2025-06-14"), recurrence: .everyNDays(1),
                status: .pending, completedAt: nil, notificationID: nil, groupID: nil,
                createdAt: base, updatedAt: base
            ),
            CareReminder(
                id: UUID(), plantID: UUID(), actionTypeID: nil, actionNameSnapshot: nil,
                title: "施肥", dueAt: date("2025-06-15", time: "18:00"), recurrence: .everyNWeeks(1),
                status: .pending, completedAt: nil, notificationID: nil, groupID: nil,
                createdAt: base, updatedAt: base
            ),
            CareReminder(
                id: UUID(), plantID: UUID(), actionTypeID: nil, actionNameSnapshot: nil,
                title: "换盆", dueAt: date("2025-06-20"), recurrence: .everyNMonths(1),
                status: .pending, completedAt: nil, notificationID: nil, groupID: nil,
                createdAt: base, updatedAt: base
            )
        ]
        let buckets = ReminderGrouping.pendingBuckets(
            reminders: bucketSource,
            now: date("2025-06-15", time: "12:00"),
            calendar: calendar
        )
        XCTAssertEqual(buckets.map(\.title), ["逾期", "今天", "即将到期"])
    }

    // MARK: - Order parsing

    func testOrderParserExtractsFields() {
        let text = """
        淘宝订单
        订单号：123456789012345
        2024-05-01 10:22
        店铺：花艺工作室
        白锦龟背竹 一物一拍 带盆
        规格：14cm盆
        实付 ¥420.00
        """
        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: text, now: date("2025-06-15"))
        XCTAssertEqual(draft.amountText, "420.00")
        XCTAssertEqual(draft.platform, "淘宝")
        XCTAssertEqual(draft.storeName, "花艺工作室")
        XCTAssertEqual(draft.orderNumber, "123456789012345")
        XCTAssertEqual(draft.acquiredAt, date("2024-05-01", time: "00:00"))
        XCTAssertTrue(draft.plantName.contains("白锦龟背竹"))
        XCTAssertEqual(draft.specification, "14cm盆")
        XCTAssertFalse(draft.lowConfidenceFields.contains(.amount))
        XCTAssertFalse(draft.lowConfidenceFields.contains(.purchaseDate))
    }

    func testOrderParserPrefersActualPaidAmount() {
        let text = """
        商品价格 ¥68.00
        实付款 ¥58.00
        """
        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: text, now: date("2025-06-15"))
        XCTAssertEqual(draft.amountText, "58.00")
        XCTAssertFalse(draft.lowConfidenceFields.contains(.amount))
    }

    func testOrderParserHandlesMultilineAmountAndProductTitle() {
        let text = """
        闲鱼
        卖家昵称：三の6
        带香味三角三唇小鲑鱼蝴蝶兰，2.8寸蜡质花
        商品价格 ¥68.00
        实付
        ¥ 58.00
        订单号：MOCK-20250501-001
        """
        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: text, now: date("2025-06-15"))
        XCTAssertEqual(draft.amountText, "58.00")
        XCTAssertEqual(draft.plantName, "带香味三角三唇小鲑鱼蝴蝶兰")
        XCTAssertEqual(draft.storeName, "三の6")
        XCTAssertEqual(draft.platform, "闲鱼")
        XCTAssertEqual(draft.orderNumber, "MOCK-20250501-001")
    }

    func testOrderParserAmountFallsBackToTotal() {
        let text = """
        原价 ¥68.00
        单价 ¥58.00
        合计 ¥116.00
        """
        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: text, now: date("2025-06-15"))
        XCTAssertEqual(draft.amountText, "116.00")
    }

    func testOrderParserDetectsPlatformFromDomain() {
        let draft = LocalOrderParser(calendar: calendar).parse(
            ocrText: "来源 goofish.com 商品 蝴蝶兰",
            now: date("2025-06-15")
        )
        XCTAssertEqual(draft.platform, "闲鱼")
    }

    func testOCRSelectorIgnoresAccidentalAppScreenshot() {
        let appScreenshotText = """
        白锦龟背竹
        已陪伴 401 天
        活 2 年
        阳台 · 淘宝
        当前生长状态
        出花梗 · 第 1 天
        切换状态
        查看状态历史
        记养护
        写日志
        加照片
        """
        let orderText = """
        闲鱼
        卖家昵称：三の6
        带香味三角三唇小鲑鱼蝴蝶兰，2.8寸蜡质花
        实付款 ¥58.00
        订单号：MOCK-20250501-001
        """
        let selector = OrderOCRTextSelector(calendar: calendar, now: date("2025-06-15"))
        let selection = selector.select(from: [appScreenshotText, orderText])
        XCTAssertEqual(selection.includedIndices, [1])
        XCTAssertEqual(selection.ignoredCount, 1)
        XCTAssertTrue(selection.text.contains("实付款"))
        XCTAssertFalse(selection.text.contains("已陪伴"))

        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: selection.text, now: date("2025-06-15"))
        XCTAssertEqual(draft.plantName, "带香味三角三唇小鲑鱼蝴蝶兰")
        XCTAssertEqual(draft.amountText, "58.00")
        XCTAssertEqual(draft.orderNumber, "MOCK-20250501-001")
        XCTAssertEqual(draft.platform, "闲鱼")
    }

    func testOCRSelectorRejectsAppOnlyText() {
        let appText = """
        白锦龟背竹
        已陪伴 401 天
        当前生长状态
        出花梗 · 第 1 天
        切换状态
        """
        let selector = OrderOCRTextSelector(calendar: calendar, now: date("2025-06-15"))
        let selection = selector.select(from: [appText])
        XCTAssertTrue(selection.text.isEmpty)
        XCTAssertEqual(selection.ignoredCount, 1)
        XCTAssertTrue(selection.includedIndices.isEmpty)
    }

    func testOCRSelectorKeepsMultipleOrderScreenshots() {
        let productPage = """
        闲鱼
        白锦龟背竹 一物一拍
        商品价格 ¥68.00
        """
        let paymentPage = """
        实付款 ¥58.00
        订单号：123456789012345
        """
        let selector = OrderOCRTextSelector(calendar: calendar, now: date("2025-06-15"))
        let selection = selector.select(from: [productPage, paymentPage])
        XCTAssertEqual(Set(selection.includedIndices), Set([0, 1]))
        XCTAssertEqual(selection.ignoredCount, 0)

        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: selection.text, now: date("2025-06-15"))
        XCTAssertEqual(draft.amountText, "58.00")
        XCTAssertEqual(draft.plantName, "白锦龟背竹")
    }

    func testOrderParserMarksMissingFields() {
        let draft = LocalOrderParser(calendar: calendar).parse(ocrText: "未知文本", now: date("2025-06-15"))
        XCTAssertNil(draft.acquiredAt)
        XCTAssertTrue(draft.lowConfidenceFields.contains(.amount))
        XCTAssertTrue(draft.lowConfidenceFields.contains(.platform))
        XCTAssertTrue(draft.lowConfidenceFields.contains(.purchaseDate))
    }

    // MARK: - CSV

    func testCSVEscaping() {
        XCTAssertEqual(FivoCSV.line(["a", "b,c", "d\"e", "f\ng"]), "a,\"b,c\",\"d\"\"e\",\"f\ng\"")
        XCTAssertEqual(FivoCSV.line(["中文", "普通"]), "中文,普通")
    }
}
