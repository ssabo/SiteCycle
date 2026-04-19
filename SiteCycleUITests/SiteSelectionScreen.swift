import XCTest

struct SiteSelectionScreen {
    let app: XCUIApplication

    var cancelButton: XCUIElement { app.buttons["siteSelection.cancel"] }

    func row(for locationFullDisplayName: String) -> XCUIElement {
        app.buttons["siteSelection.row.\(locationFullDisplayName)"]
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 5) -> Bool {
        cancelButton.waitForExistence(timeout: timeout)
    }

    func selectLocation(_ fullDisplayName: String) {
        let target = row(for: fullDisplayName)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected row for \(fullDisplayName)")
        if !target.isHittable {
            target.firstMatch.swipeUp()
        }
        target.tap()
    }
}
