import XCTest

struct HistoryScreen {
    let app: XCUIApplication

    var tabButton: XCUIElement { app.tabBars.buttons["History"] }
    var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "history.row")
    }
    var activeBadge: XCUIElement { app.staticTexts["Active"] }

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
}
