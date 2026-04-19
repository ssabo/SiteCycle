import XCTest

struct OnboardingScreen {
    let app: XCUIApplication

    var skipButton: XCUIElement {
        app.buttons.matching(identifier: "onboarding.skip").firstMatch
    }

    var getStartedButton: XCUIElement {
        app.buttons.matching(identifier: "onboarding.welcome.getStarted").firstMatch
    }

    var restoreCSVButton: XCUIElement {
        app.buttons.matching(identifier: "onboarding.welcome.restoreCSV").firstMatch
    }

    var nextButton: XCUIElement {
        app.buttons.matching(identifier: "onboarding.configure.next").firstMatch
    }

    var doneButton: XCUIElement {
        app.buttons.matching(identifier: "onboarding.ready.done").firstMatch
    }

    @discardableResult
    func waitForWelcomePage(timeout: TimeInterval = 15) -> Bool {
        getStartedButton.waitForExistence(timeout: timeout)
    }

    func tapSkip() {
        skipButton.tap()
    }
}
