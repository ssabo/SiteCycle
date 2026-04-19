# UI Testing Roadmap

Tracks the remaining steps of the UI-testing rollout originally scoped in the
"Adding UI Testing to SiteCycle" plan. Each step below is designed to be
picked up by a fresh agent with no prior session context — the "Context" and
"Relevant files" subsections should be enough to get oriented without
re-reading the whole branch history.

## Current State (as of PR #67, branch `claude/ui-testing-investigation-4YoaA`)

- `SiteCycleUITests` target exists and is wired into `SiteCycle.xcodeproj`
  (scheme's `<TestAction>` references it; see
  `SiteCycle.xcodeproj/xcshareddata/xcschemes/SiteCycle.xcscheme`).
- Dedicated CI workflow: `.github/workflows/ui-tests.yml` (separate from
  `ci.yml`, `paths:`-filtered so it only runs when app or UI-test code changes).
- Launch-argument plumbing in `SiteCycle/SiteCycleApp.swift`:
  - `-uiTestMode` — forces in-memory SwiftData + `cloudKitDatabase: .none`.
  - `-resetOnboarding` — clears `hasCompletedOnboarding` so tests start on Welcome.
  - `-completeOnboarding` — sets `hasCompletedOnboarding = true` so tests skip
    straight to Home.
- Base test classes in `SiteCycleUITests/SiteCycleUITestCase.swift`:
  - `SiteCycleUITestCase` — `-uiTestMode -resetOnboarding` by default.
  - `PostOnboardingUITestCase` — `-uiTestMode -completeOnboarding`.
- Page objects already in place: `OnboardingScreen`, `HomeScreen`,
  `SiteSelectionScreen`, `SiteChangeConfirmationScreen`, `HistoryScreen`.
- Passing UI tests:
  - `LaunchSmokeTests.testColdLaunchCompletes`
  - `OnboardingFlowTests.testSkipOnboardingLandsOnHome`
  - `LogSiteChangeFlowTests.testLogSiteChangeUpdatesActiveSite`
  - `LogSiteChangeFlowTests.testLoggingSecondSiteClosesPreviousEntry`
- Accessibility identifiers present:
  - `onboarding.skip`, `onboarding.welcome.getStarted`,
    `onboarding.welcome.restoreCSV`, `onboarding.configure.next`,
    `onboarding.ready.done`
  - `home.allLocations`, `home.activeSite.label`, `home.emptyState`
  - `siteSelection.cancel`, `siteSelection.row.<fullDisplayName>`
  - `siteChangeConfirmation.cancel`, `siteChangeConfirmation.confirm`
  - `history.row`

### Key CI / xcodebuild flags

The UI-tests workflow uses these non-obvious flags — keep them when adding
steps:

- `-parallel-testing-enabled NO` and `-disable-concurrent-destination-testing`
  to avoid `** TEST EXECUTE FAILED **` from simulator-clone cleanup bugs.
- Redirect to `UITestOutput.txt` **before** piping to xcpretty (not through
  `tee`) so the capture survives xcpretty exiting early.
- The `Surface UI test failures` step emits `::error::assert-ctx(L…)` lines
  with 40 lines of context before each `file.swift:NN: error:` so reviewers
  can diagnose without downloading the xcresult artifact.
- Result bundle uploaded as artifact `ui-test-results` (also includes raw
  `UITestOutput.txt`).

### Known app-side issue

`OnboardingView`'s paged `TabView` terminates the app when transitioning
from Welcome → Configure during UI tests (Xcode 26 / iPhone 16 Pro sim).
Reproduces with both tap-driven and swipe-driven navigation. A dedicated
happy-path test was dropped in commit `b05f936`; the skip path still
covers onboarding dismissal. **Fixing this crash is not part of the UI
testing roadmap — file a separate bug.**

---

## Step 3 — History, HistoryEdit, Delete flows

### Goal
Cover the core post-log flows: viewing the history list, editing an entry
(location / start / end / note), and deleting entries (swipe + confirm).

### Context
`HistoryView` (`SiteCycle/Views/HistoryView.swift`) already has
`.accessibilityIdentifier("history.row")` on each row. The row is a
`NavigationLink` that pushes `HistoryEditView`. Filters (date range,
location) are in the same file. Swipe-to-delete + confirmation dialog is
wired inside `HistoryView`.

No identifiers currently exist on `HistoryEditView`, filters, delete
confirmation, or empty-state. Adding them is the bulk of this step.

### Tasks
1. **Add identifiers** (`<screen>.<element>` convention) to:
   - `HistoryView`: `history.filter.dateRange`, `history.filter.location`,
     `history.emptyState`, `history.row.<entryID>` (swap the current static
     `"history.row"` for a per-row ID so tests can target a specific entry),
     `history.deleteButton`, `history.deleteConfirmation.confirm`,
     `history.deleteConfirmation.cancel`.
   - `HistoryEditView`: `historyEdit.locationPicker`,
     `historyEdit.startTime`, `historyEdit.endTime`, `historyEdit.note`,
     `historyEdit.save`, `historyEdit.cancel`.
2. **Extend `HistoryScreen`** (`SiteCycleUITests/HistoryScreen.swift`) with
   helpers: `tapRow(entryID:)`, `applyLocationFilter(_:)`,
   `applyDateRange(_:_:)`, `swipeToDelete(row:)`, `confirmDelete()`.
3. **Create `HistoryEditScreen`** page object mirroring the other page
   objects' style.
4. **Create `HistoryFlowTests.swift`** (`PostOnboardingUITestCase` subclass,
   with a fixture that pre-seeds 3–5 entries — see Step 3a below for the
   fixture seeding mechanism). Tests:
   - `testHistoryListRendersSeededEntries`
   - `testLocationFilterLimitsRowsToOneLocation`
   - `testEditingEntryNoteSaves` (open row → change note → save →
     verify row re-renders with new note text)
   - `testEditingEntryStartTimeUpdatesDuration`
   - `testSwipeToDeleteRemovesRow`
   - `testCancellingDeleteKeepsRow`
5. **Register new files** in `SiteCycle.xcodeproj/project.pbxproj` per the
   "Adding Files to the Xcode Project" section of `CLAUDE.md`. Use the
   next sequential hex IDs; the last UI-test files used `0072–0078` /
   `0172–0178`, so start at `0079` / `0179`.

### Step 3a — Fixture seeding (blocker for Step 3 onward)

Several later tests need pre-seeded history. Add this before writing
history tests:

1. Extend `SiteCycleApp.applyUITestLaunchArguments()` (or a new sibling
   helper called from `ContentView.onAppear` behind `-uiTestMode`) to
   handle `-seedHistory <fixture-name>`.
2. Create `SiteCycleUITests/Fixtures/` (new folder in the project) with:
   - `BasicHistoryFixture.json` — 3 entries across 3 locations over 5 days.
   - `RecommendationFixture.json` — 5 recent entries so the selection
     sheet's recommended/avoid badges are deterministic.
3. Add a helper (Swift file inside the app target, guarded by
   `ProcessInfo.processInfo.arguments.contains("-uiTestMode")`) that loads
   the requested fixture JSON from the test bundle and inserts rows into
   the in-memory `ModelContext` before the first view renders.

### Verification
- `xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:SiteCycleUITests/HistoryFlowTests CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO` passes locally.
- The new identifiers don't break unit tests.
- CI's UI-tests workflow is still green.

---

## Step 4 — Settings & Location Management flows

### Goal
Verify target-duration stepper, absorption-threshold stepper, toggling a
default location off, adding a custom zone, and soft/hard-deleting
locations.

### Context
- Settings is reached via a gear icon on `HomeView`; it's presented as a
  sheet (see `HomeView.swift`).
- `SettingsView` (`SiteCycle/Views/SettingsView.swift`) uses
  `@AppStorage` for `targetDurationHours` and `absorptionAlertThreshold`.
  Values persist across launches — test relaunch behavior by calling
  `app.terminate(); app.launch()`.
- `LocationConfigView` (`SiteCycle/Views/LocationConfigView.swift`) is
  reached from Settings. It handles enable-toggle, add-custom, and
  delete (soft when history exists, hard otherwise).

### Tasks
1. Add identifiers:
   - `HomeView`: `home.settingsButton`.
   - `SettingsView`: `settings.targetDurationStepper`,
     `settings.targetDuration.value`, `settings.absorptionThresholdStepper`,
     `settings.absorptionThreshold.value`, `settings.close`.
   - `LocationConfigView`: `locationConfig.toggle.<zone>`,
     `locationConfig.addCustomZone`, `locationConfig.row.<zone>`,
     `locationConfig.editMode`.
   - `AddCustomZoneSheet`: `addCustomZone.bodyPart`,
     `addCustomZone.qualifier`, `addCustomZone.hasLateralityToggle`,
     `addCustomZone.save`, `addCustomZone.cancel`.
2. Create page objects:
   - `SettingsScreen.swift`
   - `LocationConfigScreen.swift`
   - `AddCustomZoneScreen.swift`
3. Create `SettingsFlowTests.swift` and `LocationManagementFlowTests.swift`
   (both `PostOnboardingUITestCase`). Tests:
   - `testTargetDurationStepperPersistsAcrossRelaunch`
   - `testAbsorptionThresholdStepperPersistsAcrossRelaunch`
   - `testDisablingAllLocationsIsPrevented` (lastEnabled guard)
   - `testAddingCustomZoneAppearsInSelectionSheet`
   - `testHardDeletingCustomZoneWithoutHistoryRemovesIt`
   - `testSoftDeletingZoneWithHistoryKeepsRecordsButHidesFromSelection`
4. Register new files in pbxproj.

### Verification
Same as Step 3.

---

## Step 5 — Statistics, Recommendation badges, CSV smoke

### Goal
Verify charts render with seeded data, the site-selection sheet shows
correct recommended/avoid badges, and CSV export/import entry points are
present (sheets open — don't drive the system share sheet).

### Context
- `StatisticsView` uses Swift Charts. Chart views don't expose data via
  accessibility by default — set `.accessibilityLabel(...)` derived from
  the underlying data summary so tests can assert non-empty content
  rather than pixel state.
- `SiteSelectionSheet` already tags rows with
  `siteSelection.row.<fullDisplayName>`. Add `.recommended` / `.avoid`
  badge identifiers so tests can count them.
- CSV export/import entry points live in `SettingsView`. Tapping them
  presents the system share sheet / file picker — stop at "sheet is
  presented" to keep the test stable (the system UI is out of reach of
  XCUITest without fragile privateAPI tricks).

### Tasks
1. Add identifiers:
   - `StatisticsView`: `statistics.tab`, `statistics.chart.<name>`,
     `statistics.perLocation.row.<zone>`, `statistics.emptyState`.
   - `SiteSelectionSheet`: `siteSelection.row.<name>.badge.recommended`,
     `siteSelection.row.<name>.badge.avoid`.
   - `SettingsView`: `settings.exportCSV`, `settings.importCSV`.
2. Create page objects: `StatisticsScreen.swift`, extend
   `SiteSelectionScreen` with badge accessors.
3. Create `StatisticsFlowTests.swift`, `RecommendationFlowTests.swift`,
   and add a CSV-smoke test in `SettingsFlowTests.swift`. Tests:
   - `testStatisticsTabRendersWithSeededData` (seed via
     `RecommendationFixture`).
   - `testStatisticsShowsEmptyStateWithNoData`
   - `testRecommendationBadgesHighlightThreeMostAndLeastRecent`
   - `testExportCSVPresentsShareSheet`
   - `testImportCSVPresentsFilePicker`
4. Register new files in pbxproj.

### Verification
Same as Step 3.

---

## Step 6 (optional) — Fix the Welcome → Configure crash and re-enable happy-path test

### Context
Commit `b05f936` dropped `testWelcomeToConfigureToReadyHappyPath` because
the app terminates during the paged TabView transition. Before re-adding
the test, the underlying crash needs to be diagnosed on a Mac with Xcode
(CI-only investigation isn't sufficient — the xcresult crash log is the
definitive source). Candidates to investigate:

- `LocationConfigView`'s `List` + `.toolbar { EditButton() }` rendered
  inside a paged TabView page (no surrounding `NavigationStack`).
- SwiftData `@Query` refiring as pages lazy-render inside the scroll view.
- Re-entrant `onAppear` on `ContentView` when the `fullScreenCover`
  dismisses.

### Deliverable
Once the app-side crash is fixed, re-add the test in
`SiteCycleUITests/OnboardingFlowTests.swift` using plain `tap()` calls
(the swipe fallback from the old implementation is not needed).

---

## Suggested Rollout Order

One PR per step. Each step is roughly additive:

1. **Step 3a** (fixture seeding) — small, foundational. Land first.
2. **Step 3** (History + Edit + Delete).
3. **Step 4** (Settings + Location Management).
4. **Step 5** (Statistics + Recommendation + CSV smoke).
5. **Step 6** (optional) only after the crash is reproduced locally.
