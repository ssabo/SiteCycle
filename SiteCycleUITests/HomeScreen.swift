import XCTest

struct HomeScreen {
    let app: XCUIApplication

    var allLocationsButton: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "home.allLocations")
            .firstMatch
    }

    var activeSiteLabel: XCUIElement { activeSiteLabelAny }

    var activeSiteLabelAny: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "home.activeSite.label")
            .firstMatch
    }

    var emptyStateLabel: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "home.emptyState")
            .firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 20) -> Bool {
        // Either the empty-state button or an active-site label means the
        // Home screen is ready.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if allLocationsButton.exists || activeSiteLabelAny.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
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
