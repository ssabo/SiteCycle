import XCTest

struct HistoryScreen {
    let app: XCUIApplication

    var tabButton: XCUIElement { app.tabBars.buttons["History"] }

    /// All rows on the history list (per-entry identifiers `history.row.<uuid>`).
    var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history.row.' AND NOT (identifier ENDSWITH '.deleteButton')")
        )
    }

    /// "Active" badges rendered on rows whose entry has no end time.
    var activeBadges: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Active"))
    }

    func open() {
        XCTAssertTrue(tabButton.waitForExistence(timeout: 10), "History tab not found")
        tabButton.tap()
    }

    @discardableResult
    func waitForRowCount(_ expected: Int, timeout: TimeInterval = 5) -> Bool {
        waitForCount(of: rows, expected, timeout: timeout)
    }

    @discardableResult
    func waitForActiveBadgeCount(_ expected: Int, timeout: TimeInterval = 5) -> Bool {
        waitForCount(of: activeBadges, expected, timeout: timeout)
    }

    private func waitForCount(of query: XCUIElementQuery, _ expected: Int, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
