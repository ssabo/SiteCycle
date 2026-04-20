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

    /// Replaces the note field's contents. Taps to focus, waits for the
    /// keyboard, clears via Select-All + delete (the only reliable way to
    /// clear a multi-line SwiftUI TextField from XCUITest), types the new
    /// text, then verifies the value changed. The explicit verification
    /// turns a silent typing no-op into an actionable failure at the
    /// interaction site instead of downstream.
    func setNote(_ text: String) {
        let field = noteField
        XCTAssertTrue(field.waitForExistence(timeout: 5), "historyEdit.note not found")
        XCTAssertTrue(field.isHittable, "historyEdit.note is not hittable")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "keyboard did not appear after tapping note field (tap missed the editable control)")

        // Select any existing text with a triple-tap, then let typeText replace it.
        // `doubleTap` selects a word; triple-tap selects the line/paragraph in iOS.
        if let existing = field.value as? String,
           !existing.isEmpty,
           existing != "Add a note..." {
            // Tap three times via the coordinate to trigger Select-All semantics.
            let center = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.tap()
            center.tap()
            // Select-All via long-press menu as a fallback if triple-tap
            // doesn't land — simpler to just delete char-by-char with an
            // upper-bound count.
            let deletion = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4)
            field.typeText(deletion)
        }

        field.typeText(text)

        let actual = (field.value as? String) ?? ""
        XCTAssertEqual(actual, text,
                       "note field expected '\(text)' but reads '\(actual)' — typeText did not land")
    }

    /// Flips the "Has End Time" toggle and verifies the switch actually
    /// changed state. Uses a coordinate tap on the trailing edge because
    /// SwiftUI's `Toggle` in a `Form` row sometimes exposes its identifier
    /// on the row container, and a centered `tap()` can land on the label
    /// area without flipping the switch.
    func toggleHasEndTime() {
        let toggle = hasEndTimeToggle
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "historyEdit.hasEndTime not found")
        let before = toggle.value as? String
        // Tap the trailing edge of the row where the UISwitch physically sits.
        let trailing = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        trailing.tap()
        let after = toggle.value as? String
        XCTAssertNotEqual(before, after,
                          "hasEndTime toggle did not flip (before=\(before ?? "nil"), after=\(after ?? "nil"))")
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
