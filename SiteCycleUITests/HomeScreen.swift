import XCTest

struct HomeScreen {
    let app: XCUIApplication

    var allLocationsButton: XCUIElement {
        app.buttons.matching(identifier: "home.allLocations").firstMatch
    }

    var activeSiteLabel: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "home.activeSite.label")
            .firstMatch
    }

    /// Either the empty-state "All Locations" button or an active-site label
    /// means the Home screen is ready.
    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 20) -> Bool {
        let readyMarkers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["home.allLocations", "home.activeSite.label"])
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"),
            object: readyMarkers
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func tapAllLocations() {
        let button = allLocationsButton
        XCTAssertTrue(button.waitForExistence(timeout: 10), "home.allLocations not found")
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }
}
