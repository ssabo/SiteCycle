import XCTest

final class LocationManagementFlowTests: PostOnboardingUITestCase {

    func testDisablingAllLocationsIsPrevented() {
        app.launch()
        openManageLocations()

        let locationConfig = LocationConfigScreen(app: app)
        XCTAssertTrue(locationConfig.waitForAppearance(), "Manage Locations screen did not appear")

        for zone in ["Front Abdomen", "Side Abdomen", "Back Abdomen",
                     "Front Thigh", "Side Thigh", "Back Arm"] {
            locationConfig.toggleZone(zone)
        }

        let buttockToggle = locationConfig.zoneToggle("Buttock")
        XCTAssertTrue(buttockToggle.waitForExistence(timeout: 5), "Buttock toggle not found")
        XCTAssertEqual(buttockToggle.value as? String, "1", "Buttock should still be enabled")

        buttockToggle.tap()

        XCTAssertEqual(buttockToggle.value as? String, "1",
                       "Last-enabled guard should prevent disabling the final zone")
    }

    func testAddingCustomZoneAppearsInSelectionSheet() {
        app.launch()
        openManageLocations()
        addCustomZone(bodyPart: "UITestCustom", laterality: false)
        navigateBack(from: "Manage Locations", to: "Settings")
        navigateBack(from: "Settings", to: "SiteCycle")

        let home = HomeScreen(app: app)
        home.tapAllLocations()

        let selection = SiteSelectionScreen(app: app)
        XCTAssertTrue(selection.waitForAppearance(), "Site selection sheet did not appear")
        let customRow = selection.row(for: "UITestCustom")
        XCTAssertTrue(customRow.waitForExistence(timeout: 10),
                      "Custom zone 'UITestCustom' should appear in site selection sheet")
        selection.cancelButton.tap()
    }

    func testHardDeletingCustomZoneWithoutHistoryRemovesIt() {
        app.launch()
        openManageLocations()
        addCustomZone(bodyPart: "UITestHardDelete", laterality: false)

        let locationConfig = LocationConfigScreen(app: app)
        let row = locationConfig.zoneRow("UITestHardDelete")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "UITestHardDelete row should exist after add")

        locationConfig.swipeDeleteZone("UITestHardDelete")

        XCTAssertFalse(row.waitForExistence(timeout: 3),
                       "Hard-deleted zone should be removed from the list")
    }

    func testSoftDeletingZoneWithHistoryKeepsRecordsButHidesFromSelection() {
        app.launch()
        createCustomZoneAndLogChange(bodyPart: "UITestSoftDelete")
        softDeleteZone("UITestSoftDelete")
        verifyZoneHiddenAndHistoryPreserved(zoneName: "UITestSoftDelete")
    }

    // MARK: - Helpers

    private func openManageLocations() {
        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear")
        let settingsButton = app.buttons
            .matching(identifier: "home.settingsButton")
            .firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "home.settingsButton not found")
        settingsButton.tap()
        SettingsScreen(app: app).navigateToManageLocations()
    }

    private func addCustomZone(bodyPart: String, laterality: Bool) {
        let locationConfig = LocationConfigScreen(app: app)
        XCTAssertTrue(locationConfig.waitForAppearance(), "Manage Locations screen did not appear")
        locationConfig.tapAddCustomZone()

        let addZone = AddCustomZoneScreen(app: app)
        XCTAssertTrue(addZone.waitForAppearance(), "Add Custom Zone sheet did not appear")
        addZone.fillBodyPart(bodyPart)
        if !laterality { addZone.disableLaterality() }
        addZone.save()
        XCTAssertTrue(addZone.waitForDismissal(), "Add Custom Zone sheet did not dismiss after save")
    }

    private func navigateBack(from title: String, to destination: String) {
        let button = app.navigationBars[title].buttons[destination]
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "Back button '\(destination)' not found in nav bar '\(title)'")
        button.tap()
    }

    private func createCustomZoneAndLogChange(bodyPart: String) {
        openManageLocations()
        addCustomZone(bodyPart: bodyPart, laterality: false)
        navigateBack(from: "Manage Locations", to: "Settings")
        navigateBack(from: "Settings", to: "SiteCycle")

        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear after navigating back")
        home.tapAllLocations()

        SiteSelectionScreen(app: app).selectLocation(bodyPart)
        SiteChangeConfirmationScreen(app: app).confirm()
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear after logging site change")
    }

    private func softDeleteZone(_ zone: String) {
        openManageLocations()
        let locationConfig = LocationConfigScreen(app: app)
        XCTAssertTrue(locationConfig.waitForAppearance(), "Manage Locations screen did not appear")
        locationConfig.swipeDeleteZone(zone)

        let toggle = locationConfig.zoneToggle(zone)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Toggle for '\(zone)' not found after soft-delete")
        XCTAssertEqual(toggle.value as? String, "0",
                       "Zone toggle should be OFF after soft-delete (history exists)")

        navigateBack(from: "Manage Locations", to: "Settings")
        navigateBack(from: "Settings", to: "SiteCycle")
    }

    private func verifyZoneHiddenAndHistoryPreserved(zoneName: String) {
        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen did not appear")
        home.tapAllLocations()

        let selection = SiteSelectionScreen(app: app)
        XCTAssertTrue(selection.waitForAppearance(), "Site selection sheet did not appear")
        XCTAssertFalse(selection.row(for: zoneName).waitForExistence(timeout: 3),
                       "Soft-deleted zone must not appear in site selection sheet")
        selection.cancelButton.tap()

        let history = HistoryScreen(app: app)
        history.open()
        XCTAssertTrue(history.waitForRowCount(1, timeout: 10),
                      "History entry for the soft-deleted zone must still exist")
    }
}
