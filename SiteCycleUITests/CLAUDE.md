# SiteCycleUITests

This target holds exactly **one** XCUITest smoke test: `SmokeTests.testLogSiteChangesEndToEnd`.

- **What it does:** logs two site changes, then checks that Home and History update.
- **What it's for:** the wiring that unit tests can't see. The sheets present, Confirm saves, and `@Query` views refresh.
- **No business logic in UI tests.** Move that logic into a ViewModel and unit-test it in `SiteCycleTests/`. [`docs/ui-testing.md`](../docs/ui-testing.md) records why the broader UI suite was removed.
- **Extending the smoke test:** only for a real wiring regression. Prefer adding an assertion to the existing flow over adding a new test.

## Conventions

- **Launch arguments,** parsed in `SiteCycleApp`:
  - `-uiTestMode` forces an in-memory SwiftData store with `cloudKitDatabase: .none`.
  - `-completeOnboarding` skips onboarding.
  - `SiteCycleUITestCase` passes both.
- **Page objects:** `HomeScreen`, `SiteSelectionScreen`, `SiteChangeConfirmationScreen` and `HistoryScreen`. Add queries there, not in the test body.
- **Accessibility identifiers** follow `<screen>.<element>`, for example:
  - `home.allLocations`
  - `siteSelection.row.<fullDisplayName>`
  - `history.row.<uuid>`

  Keep the existing ones; VoiceOver tooling also relies on them.
- **Waits:** use `waitForExistence(timeout:)` or `XCTNSPredicateExpectation`. Never use `Thread.sleep`.
- **Linting:** this folder isn't covered by SwiftLint yet (`.swiftlint.yml` `included:`). Follow the same rules anyway.

## Where it runs

- **Xcode Cloud.** The `SiteCycleUITests` test plan ran in the **CI** workflow on PR #83, as the check `SiteCycle | CI | SiteCycleUITests - iOS (SiteCycle)`.
- **Locally,** run `xcodebuild test … -testPlan SiteCycleUITests`.
- **Doc mismatch:** `docs/xcode-cloud-setup.md` says it runs only in the TestFlight workflow, after merge. Treat a red UI-test check on a PR as real.
- **Onboarding:** the smoke test skips onboarding, so it doesn't exercise the known onboarding crash (review §2.5).
