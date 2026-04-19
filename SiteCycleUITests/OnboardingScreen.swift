import XCTest

struct OnboardingScreen {
    let app: XCUIApplication

    var skipButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding.skip")
            .firstMatch
    }

    var getStartedButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding.welcome.getStarted")
            .firstMatch
    }

    var restoreCSVButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding.welcome.restoreCSV")
            .firstMatch
    }

    var nextButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding.configure.next")
            .firstMatch
    }

    var doneButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding.ready.done")
            .firstMatch
    }

    @discardableResult
    func waitForWelcomePage(timeout: TimeInterval = 15) -> Bool {
        getStartedButton.waitForExistence(timeout: timeout)
    }

    func tapSkip() {
        skipButton.tap()
    }

    func completeHappyPath() {
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 15))
        getStartedButton.tap()
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10))
        nextButton.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        doneButton.tap()
    }
}
