import XCTest

struct HomeScreen {
    let app: XCUIApplication

    var allLocationsButton: XCUIElement { app.buttons["home.allLocations"] }
    var activeSiteLabel: XCUIElement { app.staticTexts["home.activeSite.label"] }
    var activeSiteLabelAny: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "home.activeSite.label").firstMatch
    }
    var emptyStateLabel: XCUIElement { app.staticTexts["home.emptyState"] }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        allLocationsButton.waitForExistence(timeout: timeout)
    }

    func tapAllLocations() {
        allLocationsButton.tap()
    }
}
