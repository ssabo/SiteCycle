import XCTest

struct SettingsScreen {
    let app: XCUIApplication

    var targetDurationStepper: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "settings.targetDurationStepper")
            .firstMatch
    }

    var targetDurationValue: XCUIElement {
        app.staticTexts.matching(identifier: "settings.targetDuration.value").firstMatch
    }

    var absorptionThresholdStepper: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "settings.absorptionThresholdStepper")
            .firstMatch
    }

    var absorptionThresholdValue: XCUIElement {
        app.staticTexts.matching(identifier: "settings.absorptionThreshold.value").firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        targetDurationStepper.waitForExistence(timeout: timeout)
    }

    func navigateToManageLocations() {
        let link = app.descendants(matching: .any)
            .matching(identifier: "settings.manageLocations")
            .firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "settings.manageLocations not found")
        link.tap()
    }

    func incrementTargetDuration() {
        let stepper = targetDurationStepper
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "targetDurationStepper not found")
        stepper.increment()
    }

    func incrementAbsorptionThreshold() {
        let stepper = absorptionThresholdStepper
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "absorptionThresholdStepper not found")
        stepper.increment()
    }
}
