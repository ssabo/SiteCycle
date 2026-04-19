import XCTest

struct SiteChangeConfirmationScreen {
    let app: XCUIApplication

    var confirmButton: XCUIElement { app.buttons["siteChangeConfirmation.confirm"] }
    var cancelButton: XCUIElement { app.buttons["siteChangeConfirmation.cancel"] }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 5) -> Bool {
        confirmButton.waitForExistence(timeout: timeout)
    }

    func confirm() {
        confirmButton.tap()
    }
}
