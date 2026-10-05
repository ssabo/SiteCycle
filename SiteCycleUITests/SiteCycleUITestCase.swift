import XCTest

/// Base class for SiteCycle UI tests. Launches the app in a deterministic state:
/// in-memory storage, no CloudKit, onboarding already completed.
class SiteCycleUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestMode", "-completeOnboarding"]
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }
}
