import XCTest

struct HistoryScreen {
    let app: XCUIApplication

    var tabButton: XCUIElement { app.tabBars.buttons["History"] }

    /// All rows on the history list. Uses a BEGINSWITH predicate so it matches
    /// the per-entry identifier pattern `history.row.<uuid>`.
    var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.'")
        )
    }

    var activeBadge: XCUIElement { app.staticTexts["Active"] }

    var emptyState: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "history.emptyState")
            .firstMatch
    }

    var locationFilter: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "history.filter.location")
            .firstMatch
    }

    var dateRangeFilter: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "history.filter.dateRange")
            .firstMatch
    }

    var deleteButton: XCUIElement {
        app.buttons.matching(identifier: "history.deleteButton").firstMatch
    }

    // SwiftUI's `.confirmationDialog` does not reliably forward the
    // `.accessibilityIdentifier` modifier through to the underlying
    // UIAlertAction buttons (the `.cancel`-role button in particular strips
    // it on iOS 17+). Match these by label instead — only one dialog is on
    // screen at a time, so the labels are unambiguous.
    var confirmDeleteButton: XCUIElement {
        app.buttons["Delete"].firstMatch
    }

    var cancelDeleteButton: XCUIElement {
        app.buttons["Cancel"].firstMatch
    }

    func open() {
        tabButton.tap()
    }

    @discardableResult
    func waitForAppearance(timeout: TimeInterval = 10) -> Bool {
        tabButton.waitForExistence(timeout: timeout)
    }

    func rowCount() -> Int {
        rows.count
    }

    /// Polls until the row count matches `expected`. Useful right after the
    /// history list first renders from the in-memory store.
    @discardableResult
    func waitForRowCount(_ expected: Int, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: rows)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Returns the row element at the given zero-based index among currently
    /// rendered rows. Rows are sorted most-recent-first by the view model.
    func row(at index: Int) -> XCUIElement {
        rows.element(boundBy: index)
    }

    func tapRow(at index: Int) {
        let target = row(at: index)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "history row at \(index) not found")
        target.tap()
    }

    /// Selects an option from the inline Location filter Picker. Pass
    /// "All Locations" to clear the filter.
    func applyLocationFilter(_ optionLabel: String) {
        let filter = locationFilter
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "history.filter.location not found")
        filter.tap()
        let option = app.buttons[optionLabel]
        XCTAssertTrue(option.waitForExistence(timeout: 5),
                      "location filter option '\(optionLabel)' not found")
        option.tap()
    }

    /// Selects one of the preset Date Range options: "Last 7 days",
    /// "Last 30 days", "Last 90 days", "All Time".
    func applyDateRange(_ optionLabel: String) {
        let filter = dateRangeFilter
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "history.filter.dateRange not found")
        filter.tap()
        let option = app.buttons[optionLabel]
        XCTAssertTrue(option.waitForExistence(timeout: 5),
                      "date range option '\(optionLabel)' not found")
        option.tap()
    }

    /// Swipes the given row left to reveal the trailing delete action, then
    /// taps the exposed delete button. Leaves the confirmation dialog open.
    func swipeToDelete(row: XCUIElement) {
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row not found for swipe-to-delete")
        row.swipeLeft()
        let button = deleteButton
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "history.deleteButton not revealed after swipe")
        button.tap()
    }

    func confirmDelete() {
        let button = confirmDeleteButton
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "history.deleteConfirmation.confirm not found")
        button.tap()
    }

    func cancelDelete() {
        let button = cancelDeleteButton
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "history.deleteConfirmation.cancel not found")
        button.tap()
    }
}
