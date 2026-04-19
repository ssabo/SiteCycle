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
        // Prefer the UISwitch element so `tap()` hits the toggle directly.
        // Fall back to any descendant with the identifier because SwiftUI
        // sometimes attaches the identifier to the Form row container rather
        // than the switch — tapping the row still toggles the state on iOS.
        let direct = app.switches.matching(identifier: "historyEdit.hasEndTime").firstMatch
        if direct.exists { return direct }
        return app.descendants(matching: .any)
            .matching(identifier: "historyEdit.hasEndTime")
            .firstMatch
    }

    var noteField: XCUIElement {
        // `TextField(..., axis: .vertical)` renders as a UITextView on iOS
        // 17+ but falls back to a UITextField on older runtimes. Prefer the
        // typed queries so `tap()` hits the editable control rather than a
        // Section-row container that happens to inherit the identifier.
        let textView = app.textViews.matching(identifier: "historyEdit.note").firstMatch
        if textView.exists { return textView }
        let textField = app.textFields.matching(identifier: "historyEdit.note").firstMatch
        if textField.exists { return textField }
        return app.descendants(matching: .any)
            .matching(identifier: "historyEdit.note")
            .firstMatch
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        saveButton.waitForExistence(timeout: timeout)
    }

    /// Replaces the note field's contents. Taps into the field, waits for
    /// the keyboard, clears existing text, then types the replacement. The
    /// keyboard wait matters on iOS 17+ where `tap()` returns before the
    /// field is actually first-responder, causing `typeText` to silently no-op.
    func setNote(_ text: String) {
        let field = noteField
        XCTAssertTrue(field.waitForExistence(timeout: 5), "historyEdit.note not found")
        field.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
        if let existing = field.value as? String, !existing.isEmpty {
            let deletion = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
            field.typeText(deletion)
        }
        field.typeText(text)
    }

    /// Flips the "Has End Time" toggle. SwiftUI's `.accessibilityIdentifier`
    /// on a `Toggle` lands on the row container rather than the UISwitch on
    /// iOS 17+, so the query accepts any element with the identifier.
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
