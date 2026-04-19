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

    /// Walks Welcome → Configure → Ready. The paged TabView sometimes swallows
    /// taps on the "Get Started"/"Next" buttons, so fall back to a horizontal
    /// swipe if the next page doesn't appear in time.
    func completeHappyPath() {
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 15),
                      "Welcome page did not appear")
        tapOrSwipeToAdvance(button: getStartedButton, nextPageButton: nextButton)
        XCTAssertTrue(nextButton.waitForExistence(timeout: 20),
                      "Configure Locations page did not appear after Get Started")
        tapOrSwipeToAdvance(button: nextButton, nextPageButton: doneButton)
        XCTAssertTrue(doneButton.waitForExistence(timeout: 20),
                      "Ready page did not appear after Next")
        doneButton.tap()
    }

    private func tapOrSwipeToAdvance(button: XCUIElement, nextPageButton: XCUIElement) {
        button.tap()
        if nextPageButton.waitForExistence(timeout: 5) { return }
        app.swipeLeft()
        _ = nextPageButton.waitForExistence(timeout: 5)
    }
}
