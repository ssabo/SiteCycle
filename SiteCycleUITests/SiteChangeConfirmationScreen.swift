import XCTest

struct SiteChangeConfirmationScreen {
    let app: XCUIApplication

    var confirmButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "siteChangeConfirmation.confirm")
            .firstMatch
    }

    var cancelButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "siteChangeConfirmation.cancel")
            .firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        confirmButton.waitForExistence(timeout: timeout)
    }

    func confirm() {
        confirmButton.tap()
    }
}
