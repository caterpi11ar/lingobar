import XCTest

final class LingobarUITests: XCTestCase {
    func testAPIKeyFieldOnlyAppearsForLLMProviders() throws {
        let suite = "LingobarUITests.\(UUID().uuidString)"
        let databasePath = NSTemporaryDirectory().appending("lingobar-ui-\(UUID().uuidString).sqlite")

        let app = launchApp(settingsSuite: suite, databasePath: databasePath)
        XCTAssertTrue(app.buttons["settings.save"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.secureTextFields["settings.apiKey"].exists)

        selectPopupValue(app, popup: app.popUpButtons["settings.provider"], value: "OpenAI")
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 2))

        selectPopupValue(app, popup: app.popUpButtons["settings.provider"], value: "Google Translate")
        XCTAssertFalse(app.secureTextFields["settings.apiKey"].exists)
    }

    func testSettingsPersistAcrossRelaunchAndStatsViewLoads() throws {
        let suite = "LingobarUITests.\(UUID().uuidString)"
        let databasePath = NSTemporaryDirectory().appending("lingobar-ui-\(UUID().uuidString).sqlite")

        let app = launchApp(settingsSuite: suite, databasePath: databasePath)
        XCTAssertTrue(app.buttons["settings.save"].waitForExistence(timeout: 5))

        selectPopupValue(app, popup: app.popUpButtons["settings.theme"], value: "深色")
        selectPopupValue(app, popup: app.popUpButtons["settings.polling"], value: "1000 ms")
        selectPopupValue(app, popup: app.popUpButtons["settings.provider"], value: "OpenAI")
        sleep(1)

        app.terminate()

        let relaunched = launchApp(settingsSuite: suite, databasePath: databasePath)
        XCTAssertTrue(relaunched.buttons["settings.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.popUpButtons["settings.theme"].value as? String, "深色")
        XCTAssertEqual(relaunched.popUpButtons["settings.polling"].value as? String, "1000 ms")
        XCTAssertEqual(relaunched.popUpButtons["settings.provider"].value as? String, "OpenAI")
        XCTAssertTrue(relaunched.staticTexts["stats.totalTranslations"].exists)
        XCTAssertTrue(relaunched.staticTexts["stats.totalCharacters"].exists)
        XCTAssertTrue(relaunched.staticTexts["stats.successRate"].exists)
    }

    private func launchApp(settingsSuite: String, databasePath: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "LINGOBAR_UI_TEST_MODE": "1",
            "LINGOBAR_SETTINGS_SUITE": settingsSuite,
            "LINGOBAR_DATABASE_PATH": databasePath,
            "LINGOBAR_USE_INSECURE_TEST_CREDENTIALS": "1",
            "LINGOBAR_DISABLE_NOTIFICATIONS": "1",
        ]
        app.launch()
        return app
    }

    private func selectPopupValue(_ app: XCUIApplication, popup: XCUIElement, value: String) {
        let item = app.menuItems[value]

        for attempt in 0 ..< 3 {
            popup.click()
            if item.waitForExistence(timeout: 2) {
                item.click()
                return
            }

            if attempt < 2 {
                popup.click()
            }
        }

        XCTFail("Failed to find \(value) in popup menu")
    }
}
