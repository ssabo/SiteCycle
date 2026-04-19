# UI Testing Roadmap

Tracks the remaining steps of the UI-testing rollout originally scoped in the
"Adding UI Testing to SiteCycle" plan. Each step below is designed to be
picked up by a fresh agent with no prior session context — the "Context" and
"Relevant files" subsections should be enough to get oriented without
re-reading the whole branch history.

## Current State (as of PR #68, branch `claude/implement-ui-testing-step-3a-xfQIR`)

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
  - `-seedHistory <FixtureName>` — loads a bundled fixture JSON and inserts
    deterministic `SiteChangeEntry` rows into the in-memory container before
    the first view renders (Step 3a).
- Base test classes in `SiteCycleUITests/SiteCycleUITestCase.swift`:
  - `SiteCycleUITestCase` — `-uiTestMode -resetOnboarding` by default.
  - `PostOnboardingUITestCase` — `-uiTestMode -completeOnboarding`.
- Page objects already in place: `OnboardingScreen`, `HomeScreen`,
  `SiteSelectionScreen`, `SiteChangeConfirmationScreen`, `HistoryScreen`,
  `HistoryEditScreen`.
- Passing UI tests:
  - `LaunchSmokeTests.testColdLaunchCompletes`
  - `OnboardingFlowTests.testSkipOnboardingLandsOnHome`
  - `LogSiteChangeFlowTests.testLogSiteChangeUpdatesActiveSite`
  - `LogSiteChangeFlowTests.testLoggingSecondSiteClosesPreviousEntry`
  - `HistoryFlowTests.testHistoryListRendersSeededEntries`
  - `HistoryFlowTests.testLocationFilterLimitsRowsToOneLocation`
  - `HistoryFlowTests.testEditingEntryNoteSaves`
  - `HistoryFlowTests.testEditingEntryStartTimeUpdatesDuration`
  - `HistoryFlowTests.testSwipeToDeleteRemovesRow`
- Accessibility identifiers present:
  - `onboarding.skip`, `onboarding.welcome.getStarted`,
    `onboarding.welcome.restoreCSV`, `onboarding.configure.next`,
    `onboarding.ready.done`
  - `home.allLocations`, `home.activeSite.label`, `home.emptyState`
  - `siteSelection.cancel`, `siteSelection.row.<fullDisplayName>`
  - `siteChangeConfirmation.cancel`, `siteChangeConfirmation.confirm`
  - `history.row.<entryID>`, `history.filter.location`,
    `history.filter.dateRange`, `history.emptyState`,
    `history.deleteButton`, `history.deleteConfirmation.confirm`
  - `historyEdit.locationPicker`, `historyEdit.startTime`,
    `historyEdit.endTime`, `historyEdit.hasEndTime`, `historyEdit.note`,
    `historyEdit.save`, `historyEdit.cancel`
- Fixtures bundled under `SiteCycleUITests/Fixtures/`:
  - `BasicHistoryFixture.json` — 3 entries across 3 locations spanning 5 days
    (one Active / no end time, two completed with durations).

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

## Step 3 — History, HistoryEdit, Delete flows  ✅ Completed

Shipped in PR #68 (commits `b6e9651` for Step 3a fixture seeding,
`40987d8` for the Step 3 history/edit/delete suite). 5 tests passing; one
originally-planned test was deferred — see the Appendix for details.

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

### Step 3a — Fixture seeding (blocker for Step 3 onward)  ✅ Completed

Shipped in commit `b6e9651`. `-seedHistory <FixtureName>` is wired into
`SiteCycleApp` and loads JSON from the app bundle before first render.
`BasicHistoryFixture.json` was added; `RecommendationFixture.json` was
deferred (see Appendix — it belongs with Step 5).

Original task list, for reference:

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

1. ~~**Step 3a** (fixture seeding)~~ — ✅ landed in `b6e9651`.
2. ~~**Step 3** (History + Edit + Delete)~~ — ✅ landed in `40987d8` (PR #68).
3. **Step 4** (Settings + Location Management) — next.
4. **Step 5** (Statistics + Recommendation + CSV smoke).
5. **Step 6** (optional) only after the crash is reproduced locally.

---

## Appendix — Descoped / Deferred Items

Items that were initially planned but dropped or changed during
implementation. Tracked here so we can revisit them independently rather
than having them quietly disappear from the roadmap.

### A1. `testCancellingDeleteKeepsRow` — removed from Step 3

**Original intent:** Verify that tapping Cancel on the delete-confirmation
dialog leaves the row in place (negative-path UX regression test).

**Why dropped:** On iOS 18 / Xcode 26, SwiftUI's `.confirmationDialog`
Cancel action is not reliably reachable from XCUITest. We tried:

- Explicit `.cancel`-role `Button` with `.accessibilityIdentifier(...)` —
  iOS strips the identifier from the underlying `UIAlertAction` button.
- Omitting the explicit button to let iOS auto-add one, then querying by
  label (`"Cancel"`) with both `app.buttons[...]` and an NSPredicate over
  all descendants — neither consistently found the button even after the
  dialog title was confirmed visible.

The destructive happy path (`testSwipeToDeleteRemovesRow`) still covers
the delete flow end-to-end. A comment in `HistoryFlowTests.swift`
documents the limitation.

**Re-entry criteria:** Retry once we upgrade the CI simulator past iOS 18
/ Xcode 26, or when Apple fixes confirmationDialog accessibility
forwarding. An alternative would be a coordinate-based dismissal (tap on
the darkened sheet background) — viable but brittle, and not worth the
maintenance tax until we have a real UX regression to guard against.

### A2. Start-time DatePicker driven directly — substituted with `hasEndTime` toggle

**Original intent:** `testEditingEntryStartTimeUpdatesDuration` was to
open an entry, change the start-time via the in-Form `DatePicker`, save,
and assert the row's duration string re-renders.

**Why changed:** SwiftUI in-Form `DatePicker`s render as a compact
pop-over wheel picker that XCUITest cannot drive reliably (individual
wheel columns are not queryable as `.pickerWheels` on all iOS versions,
and tapping the picker chevron to expand inline is racey).

**What shipped instead:** The test flips the `hasEndTime` toggle on the
Active entry and asserts the Active badge disappears (the row swaps the
badge for a duration string). Same edit → save → persist → re-render
path; different input vector. The rationale is captured in the test's
in-line comment.

**Re-entry criteria:** When XCUITest gains stable primitives for
driving in-Form DatePickers (or we switch the UI to a custom stepper/
text field that is trivially testable).

### A3. `tapRow(entryID:)` — substituted with positional `tapRow(at index:)`

**Original intent:** Target History rows by their `SiteChangeEntry.id.uuidString`.

**Why changed:** Our fixtures produce deterministic sort order, so
zero-based indexing against the rendered rows is simpler and just as
reliable. Per-entry identifiers (`history.row.<uuid>`) are still on each
row — tests that need to target a specific entry by ID still can via
the `rows` XCUIElementQuery, we just haven't needed that yet.

**Re-entry criteria:** If a future test asserts behavior that depends on
a specific entry's identity (not its list position), add the `entryID`
helper on top of the existing identifier.

### A4. `RecommendationFixture.json` — deferred to Step 5

**Original intent:** A second fixture (5 recent entries) so the
site-selection sheet's recommended/avoid badges are deterministic.

**Why deferred:** Step 3 only needed history-list coverage, and adding a
second fixture we wouldn't use yet risked drift. Step 5 is the natural
home for it because that's where recommendation-badge tests live.

**Re-entry criteria:** Create it as part of Step 5 alongside
`testRecommendationBadgesHighlightThreeMostAndLeastRecent`.
