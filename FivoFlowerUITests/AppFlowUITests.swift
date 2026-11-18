import XCTest

final class AppFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fivoUITestMode"] + extraArguments
        app.launch()
        return app
    }

    func testCreatePlantFromEmptyGarden() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Fivo的花花"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["花房还是空的"].waitForExistence(timeout: 20))

        app.buttons["tab.add"].tap()
        XCTAssertTrue(app.buttons["add.plant"].waitForExistence(timeout: 5))
        app.buttons["add.plant"].tap()

        let nameField = app.textFields["plant.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("测试龟背竹")

        app.buttons["plant.saveButton"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["plantCard.测试龟背竹"].waitForExistence(timeout: 10)
        )
    }

    func testInitialStageDateToggleShowsDatePicker() {
        let app = launch()
        app.buttons["tab.add"].tap()
        app.buttons["add.plant"].tap()

        let toggle = app.switches["plant.hasInitialStageDate"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["开始日期为创建当天"].exists)
        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["plant.initialStageDate"].waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(app.staticTexts["开始日期为创建当天"].waitForExistence(timeout: 5))
    }

    func testSeededPlantOpensDetailAndStageSheet() {
        let app = launch(["-seedMockPlants"])
        let card = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["plant.companionCard"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["白锦龟背竹"].exists)

        let switchButton = app.buttons["plant.switchStage"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5))
        switchButton.tap()
        XCTAssertTrue(app.navigationBars["切换生长状态"].waitForExistence(timeout: 10))
    }

    func testLongPressPlantSelectionOpensBatchCare() {
        let app = launch(["-seedMockPlants"])
        let firstCard = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20))
        firstCard.press(forDuration: 0.8)

        let batchButton = app.buttons["garden.batchCare"]
        XCTAssertTrue(batchButton.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["plantCard.蝴蝶兰"].tap()
        batchButton.tap()

        XCTAssertTrue(app.navigationBars["记养护"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已选 2 株"].waitForExistence(timeout: 5))
    }

    func testCalendarTabShowsDailyReminders() {
        let app = launch()
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.navigationBars["养护日历"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["care.calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当日没有待办"].waitForExistence(timeout: 5))
    }

    func testCalendarMarksDatesWithPendingCount() {
        let app = launch(["-seedMockPlants", "-seedCalendarReminders"])
        app.buttons["tab.calendar"].tap()
        XCTAssertTrue(app.navigationBars["养护日历"].waitForExistence(timeout: 10))

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let marker = app.descendants(matching: .any)["calendar.pendingCount.\(formatter.string(from: Date()))"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.label, "2 项")
    }

    func testPlantJournalEntryOpensJournalDetail() {
        let app = launch(["-seedMockPlants"])
        let card = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()

        app.swipeUp()
        let journalTab = app.buttons["日志"]
        XCTAssertTrue(journalTab.waitForExistence(timeout: 10))
        let tabBarTop = app.buttons["tab.garden"].frame.minY
        for _ in 0..<5 where journalTab.frame.maxY > tabBarTop - 8 {
            app.swipeUp()
        }
        journalTab.tap()

        let entries = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "plant.journalEntry."))
        for _ in 0..<5 where !entries.firstMatch.exists || entries.firstMatch.frame.maxY > tabBarTop - 8 {
            app.swipeUp()
        }
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 5))
        entries.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["日志详情"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["时间"].exists)
    }

    func testCareStatusCyclePrefillsPlantAndAction() {
        let app = launch(["-seedMockPlants"])
        let card = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()

        let setReminder = app.buttons["设置浇水周期"]
        XCTAssertTrue(setReminder.waitForExistence(timeout: 10))
        let tabBarTop = app.buttons["tab.garden"].frame.minY
        for _ in 0..<4 where setReminder.frame.maxY > tabBarTop - 8 {
            app.swipeUp()
        }
        setReminder.tap()

        XCTAssertTrue(app.navigationBars["添加周期"].waitForExistence(timeout: 10))
        let titleField = app.textFields["reminder.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertEqual(titleField.value as? String, "浇水")
        let actionPicker = app.descendants(matching: .any)["reminder.actionType"]
        XCTAssertTrue(actionPicker.label.contains("浇水"))
        let selectedCount = app.descendants(matching: .any)["reminder.selectedPlantCount"]
        XCTAssertTrue(selectedCount.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedCount.label, "已选 1 株")
        for mode in ["每 N 天", "每 N 周", "每 N 月", "每 N 年"] {
            XCTAssertTrue(app.buttons[mode].exists)
        }
        XCTAssertFalse(app.buttons["仅一次"].exists)
    }

    func testExistingCycleAlwaysOpensEditor() {
        let app = launch(["-seedMockPlants", "-seedCalendarReminders"])
        let card = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()

        let setCycle = app.buttons["设置浇水周期"]
        XCTAssertTrue(setCycle.waitForExistence(timeout: 10))
        let tabBarTop = app.buttons["tab.garden"].frame.minY
        for _ in 0..<4 where setCycle.frame.maxY > tabBarTop - 8 {
            app.swipeUp()
        }
        setCycle.tap()

        XCTAssertTrue(app.navigationBars["修改周期"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["reminder.titleField"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["reminder.titleField"].value as? String, "浇水")
        XCTAssertTrue(app.staticTexts["下次待办"].exists)
    }

    func testPlantCardStaysInsideScreenWithWideCover() {
        let app = launch(["-seedMockPlants"])
        let card = app.descendants(matching: .any)["plantCard.月季"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(card.frame.maxX, window.maxX + 1)
        XCTAssertGreaterThanOrEqual(card.frame.minX, window.minX - 1)
        XCTAssertLessThanOrEqual(card.frame.width, window.width)
    }

    func testPhotoGridShowsSquareThumbnails() {
        let app = launch(["-seedMockPlants"])
        let card = app.descendants(matching: .any)["plantCard.白锦龟背竹"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()

        app.swipeUp()
        let photosTab = app.buttons["照片"]
        XCTAssertTrue(photosTab.waitForExistence(timeout: 10))
        let tabBarTop = app.buttons["tab.garden"].frame.minY
        for _ in 0..<5 where photosTab.frame.maxY > tabBarTop - 8 {
            app.swipeUp()
        }
        photosTab.tap()

        let thumbnails = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "photoThumb."))
        for _ in 0..<4 where !thumbnails.firstMatch.exists {
            app.swipeUp()
        }
        XCTAssertTrue(thumbnails.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(thumbnails.count, 4)
    }

    func testManualLedgerEntry() {
        let app = launch(["-seedMockPlants"])
        app.buttons["tab.ledger"].tap()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 10))
        app.buttons["ledger.add"].tap()

        let titleField = app.textFields["ledger.titleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("测试支出")

        let amountField = app.textFields["ledger.amountField"]
        amountField.tap()
        amountField.typeText("12.34")

        app.buttons["ledger.save"].tap()
        XCTAssertTrue(app.staticTexts["测试支出"].waitForExistence(timeout: 10))
    }

    func testCloudBackupFromSettingsCreatesPackage() {
        let app = launch(["-seedMockPlants"])
        XCTAssertTrue(app.buttons["garden.settings"].waitForExistence(timeout: 20))
        app.buttons["garden.settings"].tap()

        let backupRow = app.staticTexts["备份与恢复"].firstMatch
        XCTAssertTrue(backupRow.waitForExistence(timeout: 10))
        backupRow.tap()

        let cloudButton = app.buttons["立即备份到 iCloud"]
        XCTAssertTrue(cloudButton.waitForExistence(timeout: 10))
        cloudButton.tap()

        XCTAssertTrue(app.staticTexts["云端备份"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'fivoflower-'")).firstMatch.exists)
    }
}
