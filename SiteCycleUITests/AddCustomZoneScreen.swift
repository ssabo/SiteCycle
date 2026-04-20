import XCTest

struct AddCustomZoneScreen {
    let app: XCUIApplication

    var bodyPartField: XCUIElement {
        app.textFields.matching(identifier: "addCustomZone.bodyPart").firstMatch
    }

    var qualifierField: XCUIElement {
        app.textFields.matching(identifier: "addCustomZone.qualifier").firstMatch
    }

    var hasLateralityToggle: XCUIElement {
        // Identifier is on the Toggle container; drill into the UISwitch child for reliable
        // value reads ("0"/"1") and tapping.
        app.descendants(matching: .any)
            .matching(identifier: "addCustomZone.hasLateralityToggle")
            .firstMatch
            .switches
            .firstMatch
    }

    var saveButton: XCUIElement {
        app.buttons.matching(identifier: "addCustomZone.save").firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        bodyPartField.waitForExistence(timeout: timeout)
    }

    func fillBodyPart(_ text: String) {
        let field = bodyPartField
        XCTAssertTrue(field.waitForExistence(timeout: 5), "addCustomZone.bodyPart not found")
        field.tap()
        field.typeText(text)
    }

    func disableLaterality() {
        let toggle = hasLateralityToggle
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "addCustomZone.hasLateralityToggle not found")
        if toggle.value as? String == "1" {
            toggle.tap()
        }
    }

    func save() {
        let button = saveButton
        XCTAssertTrue(button.waitForExistence(timeout: 5), "addCustomZone.save not found")
        button.tap()
    }

    @discardableResult
    func waitForDismissal(timeout: TimeInterval = 10) -> Bool {
        let query = app.textFields.matching(identifier: "addCustomZone.bodyPart")
        let predicate = NSPredicate(format: "count == 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
