import XCTest

final class LaunchSmokeTests: SiteCycleUITestCase {
    func testColdLaunchCompletes() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
