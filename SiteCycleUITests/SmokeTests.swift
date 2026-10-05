import XCTest

/// The single end-to-end smoke test for the iOS app. It exists to catch
/// wiring breaks that unit tests can't see — a sheet that no longer presents,
/// a confirm button that no longer saves, a list that no longer refreshes
/// from SwiftData. Business logic (closing the previous entry, recommendations,
/// location rules) is covered by the unit tests in `SiteCycleTests/`; don't add
/// more UI tests for it. See `docs/ui-testing.md` for the rationale.
final class SmokeTests: SiteCycleUITestCase {
    private let firstSite = "L Abdomen (Front)"
    private let secondSite = "R Abdomen (Front)"

    func testLogSiteChangesEndToEnd() {
        app.launch()

        logSiteChange(to: firstSite)
        logSiteChange(to: secondSite)

        let history = HistoryScreen(app: app)
        history.open()
        XCTAssertTrue(history.waitForRowCount(2),
                      "Expected 2 history rows, got \(history.rows.count)")
        XCTAssertTrue(history.waitForActiveBadgeCount(1),
                      "Exactly one entry should remain active, got \(history.activeBadges.count)")
    }

    private func logSiteChange(to locationFullDisplayName: String) {
        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear")
        home.tapAllLocations()

        let selection = SiteSelectionScreen(app: app)
        XCTAssertTrue(selection.waitForAppearance(), "Site selection sheet did not appear")
        selection.selectLocation(locationFullDisplayName)

        let confirmation = SiteChangeConfirmationScreen(app: app)
        XCTAssertTrue(confirmation.waitForAppearance(), "Confirmation sheet did not appear")
        confirmation.confirm()

        let label = home.activeSiteLabel
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", locationFullDisplayName),
            object: label
        )
        XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 10), .completed,
                       "Home should show \(locationFullDisplayName) as the active site")
    }
}
