import XCTest

final class SettingsFlowTests: SettingsUITestCase {

    func testTargetDurationStepperPersistsAcrossRelaunch() {
        app.launch()

        navigateToSettings()
        let settings = SettingsScreen(app: app)
        XCTAssertTrue(settings.waitForAppearance(), "Settings screen did not appear")

        let valueBefore = settings.targetDurationValue.label
        settings.incrementTargetDuration()
        let valueAfter = settings.targetDurationValue.label
        XCTAssertNotEqual(valueBefore, valueAfter, "Value should change after increment")

        // Relaunch without -resetSettings so @AppStorage persists across launch
        app.terminate()
        app.launchArguments = ["-uiTestMode", "-completeOnboarding"]
        app.launch()

        navigateToSettings()
        XCTAssertTrue(settings.waitForAppearance(), "Settings screen did not appear after relaunch")
        XCTAssertEqual(settings.targetDurationValue.label, valueAfter,
                       "Target duration should persist across relaunch")
    }

    func testAbsorptionThresholdStepperPersistsAcrossRelaunch() {
        app.launch()

        navigateToSettings()
        let settings = SettingsScreen(app: app)
        XCTAssertTrue(settings.waitForAppearance(), "Settings screen did not appear")

        let valueBefore = settings.absorptionThresholdValue.label
        settings.incrementAbsorptionThreshold()
        let valueAfter = settings.absorptionThresholdValue.label
        XCTAssertNotEqual(valueBefore, valueAfter, "Value should change after increment")

        app.terminate()
        app.launchArguments = ["-uiTestMode", "-completeOnboarding"]
        app.launch()

        navigateToSettings()
        XCTAssertTrue(settings.waitForAppearance(), "Settings screen did not appear after relaunch")
        XCTAssertEqual(settings.absorptionThresholdValue.label, valueAfter,
                       "Absorption threshold should persist across relaunch")
    }

    private func navigateToSettings() {
        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear")
        let settingsButton = app.buttons
            .matching(identifier: "home.settingsButton")
            .firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "home.settingsButton not found")
        settingsButton.tap()
    }
}
