import XCTest

struct HistoryEditScreen {
    let app: XCUIApplication

    var saveButton: XCUIElement {
        app.buttons.matching(identifier: "historyEdit.save").firstMatch
    }

    var cancelButton: XCUIElement {
        app.buttons.matching(identifier: "historyEdit.cancel").firstMatch
    }

    var locationPicker: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "historyEdit.locationPicker")
            .firstMatch
    }

    var startTimePicker: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "historyEdit.startTime")
            .firstMatch
    }

    var endTimePicker: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "historyEdit.endTime")
            .firstMatch
    }

    var hasEndTimeToggle: XCUIElement {
        app.switches.matching(identifier: "historyEdit.hasEndTime").firstMatch
    }

    var noteField: XCUIElement {
        // `TextField(..., axis: .vertical)` can render as either a textView or
        // textField depending on iOS version, so we match by identifier only.
        app.descendants(matching: .any)
            .matching(identifier: "historyEdit.note")
            .firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        saveButton.waitForExistence(timeout: timeout)
    }

    /// Replaces the note field's contents. Taps into the field, clears existing
    /// text, then types the replacement. Uses `textViews` because SwiftUI renders
    /// a `TextField(..., axis: .vertical)` as a multi-line text view.
    func setNote(_ text: String) {
        let field = noteField
        XCTAssertTrue(field.waitForExistence(timeout: 5), "historyEdit.note not found")
        field.tap()
        if let existing = field.value as? String, !existing.isEmpty {
            let deletion = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            field.typeText(deletion)
        }
        field.typeText(text)
    }

    func toggleHasEndTime() {
        let toggle = hasEndTimeToggle
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "historyEdit.hasEndTime not found")
        toggle.tap()
    }

    func save() {
        let button = saveButton
        XCTAssertTrue(button.waitForExistence(timeout: 5), "historyEdit.save not found")
        button.tap()
    }

    func cancel() {
        let button = cancelButton
        XCTAssertTrue(button.waitForExistence(timeout: 5), "historyEdit.cancel not found")
        button.tap()
    }
}
