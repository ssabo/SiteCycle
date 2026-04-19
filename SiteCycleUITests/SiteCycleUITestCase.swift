import XCTest

/// Base class for SiteCycle UI tests. Launches the app in a deterministic state:
/// in-memory storage, no CloudKit. Subclasses control whether onboarding is
/// reset or pre-completed by overriding `defaultLaunchArguments`.
class SiteCycleUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = defaultLaunchArguments
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    /// Starts every test on the onboarding screen with an empty in-memory store.
    var defaultLaunchArguments: [String] {
        ["-uiTestMode", "-resetOnboarding"]
    }
}

/// Base class for tests that run past the onboarding screen. Launches straight
/// into `ContentView` with onboarding marked complete.
class PostOnboardingUITestCase: SiteCycleUITestCase {
    override var defaultLaunchArguments: [String] {
        ["-uiTestMode", "-completeOnboarding"]
    }
}
