import XCTest

final class OnboardingFlowTests: SiteCycleUITestCase {
    func testSkipOnboardingLandsOnHome() {
        app.launch()

        let onboarding = OnboardingScreen(app: app)
        XCTAssertTrue(onboarding.waitForWelcomePage())
        onboarding.tapSkip()

        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen should appear after skipping onboarding")
    }

    func testWelcomeToConfigureToReadyHappyPath() {
        app.launch()

        let onboarding = OnboardingScreen(app: app)
        onboarding.completeHappyPath()

        let home = HomeScreen(app: app)
        XCTAssertTrue(home.waitForAppearance(), "Home screen should appear after completing onboarding")
    }
}
