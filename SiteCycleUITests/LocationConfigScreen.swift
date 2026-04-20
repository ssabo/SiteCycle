import XCTest

struct LocationConfigScreen {
    let app: XCUIApplication

    var addCustomZoneButton: XCUIElement {
        app.buttons.matching(identifier: "locationConfig.addCustomZone").firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        addCustomZoneButton.waitForExistence(timeout: timeout)
    }

    func zoneToggle(_ zone: String) -> XCUIElement {
        app.switches.matching(identifier: "locationConfig.toggle.\(zone)").firstMatch
    }

    func zoneRow(_ zone: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "locationConfig.row.\(zone)")
            .firstMatch
    }

    func tapAddCustomZone() {
        let button = addCustomZoneButton
        XCTAssertTrue(button.waitForExistence(timeout: 5), "locationConfig.addCustomZone not found")
        button.tap()
    }

    func toggleZone(_ zone: String) {
        let toggle = zoneToggle(zone)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "toggle for zone '\(zone)' not found")
        toggle.tap()
    }

    func swipeDeleteZone(_ zone: String) {
        let row = zoneRow(zone)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row for zone '\(zone)' not found")
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button not revealed after swipe")
        deleteButton.tap()
    }
}
