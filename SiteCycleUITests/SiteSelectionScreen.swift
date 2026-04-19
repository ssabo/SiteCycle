import XCTest

struct SiteSelectionScreen {
    let app: XCUIApplication

    var cancelButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "siteSelection.cancel")
            .firstMatch
    }

    func row(for locationFullDisplayName: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "siteSelection.row.\(locationFullDisplayName)")
            .firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        cancelButton.waitForExistence(timeout: timeout)
    }

    func selectLocation(_ fullDisplayName: String) {
        let target = row(for: fullDisplayName)
        XCTAssertTrue(target.waitForExistence(timeout: 10),
                      "Expected siteSelection row for \(fullDisplayName)")
        var attempts = 0
        while !target.isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        target.tap()
    }
}
