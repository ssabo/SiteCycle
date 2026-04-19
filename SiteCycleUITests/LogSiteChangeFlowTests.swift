import XCTest

final class LogSiteChangeFlowTests: PostOnboardingUITestCase {
    private let firstSite = "L Abdomen (Front)"
    private let secondSite = "R Abdomen (Front)"

    func testLogSiteChangeUpdatesActiveSite() {
        app.launch()

        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance())
        home.tapAllLocations()

        let selection = SiteSelectionScreen(app: app)
        XCTAssertTrue(selection.waitForAppearance())
        selection.selectLocation(firstSite)

        let confirmation = SiteChangeConfirmationScreen(app: app)
        XCTAssertTrue(confirmation.waitForAppearance())
        confirmation.confirm()

        XCTAssertTrue(home.activeSiteLabelAny.waitForExistence(timeout: 5))
        XCTAssertEqual(home.activeSiteLabelAny.label, firstSite)
    }

    func testLoggingSecondSiteClosesPreviousEntry() {
        app.launch()

        logSiteChange(to: firstSite)
        logSiteChange(to: secondSite)

        let home = HomeScreen(app: app)
        XCTAssertEqual(home.activeSiteLabelAny.label, secondSite)

        let history = HistoryScreen(app: app)
        history.open()
        XCTAssertTrue(history.waitForAppearance())

        // Give the List a moment to populate from the in-memory store.
        let predicate = NSPredicate(format: "count == 2")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: history.rows)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)

        // The newer entry is still open, the older one has been closed.
        XCTAssertEqual(history.activeBadge.firstMatch.exists ? 1 : 0, 1,
                       "Exactly one entry should remain active after logging a second site")
    }

    private func logSiteChange(to locationFullDisplayName: String) {
        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance())
        home.tapAllLocations()

        let selection = SiteSelectionScreen(app: app)
        XCTAssertTrue(selection.waitForAppearance())
        selection.selectLocation(locationFullDisplayName)

        let confirmation = SiteChangeConfirmationScreen(app: app)
        XCTAssertTrue(confirmation.waitForAppearance())
        confirmation.confirm()

        XCTAssertTrue(home.activeSiteLabelAny.waitForExistence(timeout: 5))
    }
}
