import XCTest

struct OnboardingScreen {
    let app: XCUIApplication

    var skipButton: XCUIElement { app.buttons["onboarding.skip"] }
    var getStartedButton: XCUIElement { app.buttons["onboarding.welcome.getStarted"] }
    var restoreCSVButton: XCUIElement { app.buttons["onboarding.welcome.restoreCSV"] }
    var nextButton: XCUIElement { app.buttons["onboarding.configure.next"] }
    var doneButton: XCUIElement { app.buttons["onboarding.ready.done"] }

    @discardableResult
    func waitForWelcomePage(timeout: TimeInterval = 10) -> Bool {
        getStartedButton.waitForExistence(timeout: timeout)
    }

    func tapSkip() {
        skipButton.tap()
    }

    func completeHappyPath() {
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 10))
        getStartedButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))
        nextButton.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }
}
