# SiteCycle Implementation Plan

This plan breaks the SiteCycle spec into 6 phases. Each phase is designed to be implementable in a single Claude Code session. Phases build on each other sequentially -- each assumes the prior phase is complete.

Reference: [SPEC.md](./SPEC.md)

---

## Phase 1: Project Scaffold, Data Models & App Shell

**Goal:** Create the Xcode project, define all SwiftData models with CloudKit-ready configuration, seed default locations, and set up the tab-based navigation shell.

### Deliverables

1. **Xcode project creation**
   - Create a new SwiftUI App project named `SiteCycle` targeting iOS 17.0+.
   - Configure the project with a CloudKit container identifier (`iCloud.com.sitecycle.app`) in entitlements.
   - Add the Background Modes and iCloud (CloudKit) capabilities.
   - Set up the folder structure: `Models/`, `ViewModels/`, `Views/`, `Utilities/`.

2. **SwiftData models** (see Spec sections 3.2.1, 3.3.1, 4.3)
   - `Models/Location.swift` -- SwiftData `@Model` class:
     - `id: UUID`, `zone: String`, `side: String?` (values: `"left"`, `"right"`, or `nil`), `isEnabled: Bool`, `isCustom: Bool`, `sortOrder: Int`.
     - Computed `displayName: String` -- e.g., "Left Front Abdomen" or just "Lower Back" if no side.
     - Relationship: `entries: [SiteChangeEntry]` (one-to-many, cascade delete rule on the inverse is nullify).
   - `Models/SiteChangeEntry.swift` -- SwiftData `@Model` class:
     - `id: UUID`, `startTime: Date`, `endTime: Date?`, `note: String?`.
     - Relationship: `location: Location?` (many-to-one).
     - Computed `durationHours: Double?` -- returns `nil` if `endTime` is nil.
   - Define a `VersionedSchema` (v1) so future migrations are straightforward (Spec section 4.4).

3. **Default locations seed data** (see Spec section 3.2.2)
   - `Utilities/DefaultLocations.swift` -- A function `seedDefaultLocations(context:)` that checks if locations exist and, if not, inserts the 7 default zones (each with left/right variants = 14 locations total). All enabled by default, `isCustom = false`.

4. **App entry point & ModelContainer**
   - `SiteCycleApp.swift` -- Configure `ModelContainer` for both models with CloudKit configuration. Call seed function on first launch.
   - Store a `hasCompletedOnboarding` flag in `@AppStorage` (UserDefaults) to control first-launch flow (actual onboarding UI is Phase 2).

5. **Tab bar navigation shell**
   - `Views/ContentView.swift` -- `TabView` with three tabs: Home, History, Statistics. Each tab shows a placeholder view with the tab name and SF Symbol icon (`house`, `clock`, `chart.bar`).
   - Gear icon in the navigation bar leading to a placeholder Settings screen.

### Files Created/Modified
- `SiteCycle/SiteCycleApp.swift`
- `SiteCycle/Models/Location.swift`
- `SiteCycle/Models/SiteChangeEntry.swift`
- `SiteCycle/Utilities/DefaultLocations.swift`
- `SiteCycle/Views/ContentView.swift`

### Verification
- Project builds without errors.
- Running in Simulator shows three-tab layout with placeholder content.
- Default locations are seeded into SwiftData on first launch (verify via debug print or breakpoint).

---

## Phase 2: Location Configuration & Onboarding

**Goal:** Build the location management screen and the first-launch onboarding flow so users can configure their body locations before they start logging.

### Prerequisites
- Phase 1 complete (models, seed data, tab shell).

### Deliverables

1. **Location configuration screen** (Spec sections 3.2, 7)
   - `Views/LocationConfigView.swift`:
     - List all locations grouped by zone, showing enabled/disabled state as toggles.
     - Each zone row shows the zone name and a toggle. For zones with laterality, toggling the zone toggles both left and right locations together.
     - "Add Custom Zone" button at the bottom: presents a sheet with a text field for zone name and a laterality toggle. On save, creates 1 or 2 Location records (`isCustom = true`).
     - Swipe-to-delete on custom zones (soft-delete: sets `isEnabled = false` if the zone has history, hard-delete if no history).
     - Reorder support via `EditButton` / move handles to change `sortOrder`.

2. **Settings screen** (Spec section 7)
   - `Views/SettingsView.swift`:
     - "Manage Locations" row -> navigates to `LocationConfigView`.
     - "Target Duration" row -> stepper or picker, value stored in `@AppStorage` (default: 72 hours).
     - "Absorption Alert Threshold" row -> stepper or picker, percentage stored in `@AppStorage` (default: 20%).
     - "Export Data" row -> placeholder (implemented in Phase 6).
     - "About" row -> app version display.
   - Settings accessible via gear icon in navigation bar on each tab.

3. **Onboarding flow** (Spec section 8)
   - `Views/OnboardingView.swift`:
     - **Page 1 -- Welcome:** App name, brief description, SF Symbol illustration, "Get Started" button.
     - **Page 2 -- Configure Locations:** Embedded `LocationConfigView` (or a simplified version) letting the user toggle zones on/off. "Next" button.
     - **Page 3 -- Ready:** "Log your first site change" prompt with a "Done" button.
     - On completion, set `hasCompletedOnboarding = true` in `@AppStorage`.
   - `SiteCycleApp.swift` updated: if `!hasCompletedOnboarding`, show `OnboardingView` as a full-screen cover instead of the main `ContentView`.
   - Onboarding is skippable (skip button in nav bar) -- sets flag and proceeds to main app.

### Files Created/Modified
- `SiteCycle/Views/LocationConfigView.swift` (new)
- `SiteCycle/Views/SettingsView.swift` (new)
- `SiteCycle/Views/OnboardingView.swift` (new)
- `SiteCycle/Views/ContentView.swift` (add settings navigation)
- `SiteCycle/SiteCycleApp.swift` (onboarding gate)

### Verification
- First launch shows onboarding flow. User can toggle locations and complete onboarding.
- After onboarding, subsequent launches go directly to main tab view.
- Settings -> Manage Locations allows toggling, adding custom zones, and reordering.
- Deleting a custom zone with no history removes it; with history it disables it.

---

## Phase 3: Home Screen & Site Change Logging

**Goal:** Implement the core user flow -- the home screen showing current site status, and the site selection sheet with recommendation logic.

### Prerequisites
- Phase 2 complete (locations are configured and persisted).

### Deliverables

1. **Home ViewModel** (Spec section 5.2)
   - `ViewModels/HomeViewModel.swift`:
     - Query the most recent `SiteChangeEntry` where `endTime == nil` to find the current active site.
     - Compute elapsed hours since `startTime`.
     - Compute progress fraction: `elapsedHours / targetDuration` (target from `@AppStorage`, default 72).
     - Expose: `currentLocation: Location?`, `startTime: Date?`, `elapsedHours: Double`, `progressFraction: Double`, `hasActiveSite: Bool`.

2. **Home screen UI** (Spec section 5.2)
   - `Views/HomeView.swift`:
     - If no active site: empty state with illustration and "Log Your First Site Change" button.
     - If active site: display location `displayName`, start time formatted, elapsed hours, and a circular progress ring (using SwiftUI `Canvas` or `ProgressView` with `circularStyle` and custom gauge).
     - Color the progress ring: green < 80% of target, yellow 80-100%, red > 100%.
     - Large prominent "Log Site Change" button at the bottom.
     - Tapping the button presents `SiteSelectionSheet` as a `.sheet`.

3. **Recommendation engine** (Spec section 3.1.2)
   - `ViewModels/SiteChangeViewModel.swift`:
     - Fetch all enabled locations.
     - For each location, find its most recent `SiteChangeEntry.startTime`.
     - Sort locations by most-recent-use descending. Locations never used sort to the end (treated as oldest).
     - **Avoid list:** First 3 locations (most recently used). If fewer than 3 locations have been used, only include those that have been used.
     - **Recommended list:** Last 3 locations (least recently used / never used). Must not overlap with Avoid list.
     - Handle edge cases: fewer than 6 locations, all locations never used, etc.
     - Method: `logSiteChange(location:note:)` -- creates a new `SiteChangeEntry` with `startTime = now`, closes the previous active entry by setting its `endTime = now`.

4. **Site selection sheet UI** (Spec section 5.3)
   - `Views/SiteSelectionSheet.swift`:
     - Three sections in a `List` or `ScrollView`:
       - **Avoid** section (red/orange header): shows avoid locations with warning icon (SF Symbol `exclamationmark.triangle.fill`), last-used date.
       - **Recommended** section (green header): shows recommended locations with checkmark icon (SF Symbol `checkmark.circle.fill`), last-used date or "Never used".
       - **All Locations** section: alphabetical, each showing last-used date. Locations in Avoid/Recommended are tagged with a small colored badge.
     - Tapping a location shows a confirmation view/alert:
       - Displays selected location name.
       - Optional note `TextField`.
       - "Confirm" and "Cancel" buttons.
     - On confirm: calls `logSiteChange()`, dismisses sheet.

### Files Created/Modified
- `SiteCycle/ViewModels/HomeViewModel.swift` (new)
- `SiteCycle/ViewModels/SiteChangeViewModel.swift` (new)
- `SiteCycle/Views/HomeView.swift` (new, replaces placeholder)
- `SiteCycle/Views/SiteSelectionSheet.swift` (new)

### Verification
- Home screen shows empty state on first launch (after onboarding).
- Tapping "Log Site Change" opens the sheet with Recommended section populated (all locations are "never used" initially).
- Selecting a location and confirming logs it. Home screen updates to show current site with elapsed time.
- Logging a second change closes the first entry (verify `endTime` is set).
- Avoid/Recommended lists update correctly after several site changes.

---

## Phase 4: History View

**Goal:** Build the history tab with a full chronological log, filtering, and the ability to edit/delete entries.

### Prerequisites
- Phase 3 complete (site changes are being logged).

### Step 1: Write Tests (before implementation)

Create `SiteCycleTests/HistoryViewModelTests.swift` with the following tests. All tests use an in-memory `ModelContainer` (same `makeContainer()` helper pattern as existing tests). The ViewModel under test is `HistoryViewModel(modelContext:)`.

#### Fetching & Ordering

| Test name | What it validates |
|-----------|-------------------|
| `fetchEntriesReturnsReverseChronologicalOrder` | Create 5 entries at different times. `filteredEntries` returns them newest-first. |
| `fetchEntriesIncludesActiveEntry` | An entry with `endTime == nil` appears in results with no crash. |
| `fetchEntriesEmptyHistoryReturnsEmptyArray` | No entries exist → `filteredEntries` returns `[]`. |

#### Filtering by Location

| Test name | What it validates |
|-----------|-------------------|
| `filterByLocationReturnsOnlyMatchingEntries` | Create entries for 3 locations. Set `locationFilter` to one location. Only that location's entries appear. |
| `filterByLocationNilReturnsAllEntries` | `locationFilter` is nil → all entries returned. |
| `filterByDisabledLocationStillShowsHistory` | Entries tied to a disabled location still appear when that location is selected as filter. |

#### Filtering by Date Range

| Test name | What it validates |
|-----------|-------------------|
| `filterByDateRangeReturnsOnlyEntriesInRange` | Create entries spanning 60 days. Set a 7-day range. Only entries within that window appear. |
| `filterByDateRangeIncludesEdgeDates` | An entry whose `startTime` is exactly on the start or end boundary is included. |
| `filterByDateRangeNilReturnsAllEntries` | No date filter → all entries returned. |

#### Combined Filters

| Test name | What it validates |
|-----------|-------------------|
| `combinedLocationAndDateFiltersApplyTogether` | Set both a location filter and a date range. Only entries matching *both* criteria appear. |

#### Editing

| Test name | What it validates |
|-----------|-------------------|
| `editEntryUpdatesLocation` | Change an entry's location to a different one. Fetch confirms the new location persists. |
| `editEntryUpdatesStartTime` | Change `startTime`. Fetch confirms the new time. |
| `editEntryUpdatesEndTime` | Set `endTime` on an active entry. Fetch confirms duration is now computable. |
| `editEntryClearsEndTime` | Set `endTime` to nil on a completed entry. Entry becomes active again. |
| `editEntryUpdatesNote` | Change the note text. Fetch confirms the update. |

#### Deleting

| Test name | What it validates |
|-----------|-------------------|
| `deleteEntryRemovesFromPersistence` | Delete an entry. Fetch confirms count decremented and entry is gone. |
| `deleteActiveEntrySucceeds` | Deleting the currently active entry (no `endTime`) works without crash. |
| `deleteOnlyEntryLeavesEmptyHistory` | Delete the sole entry. `filteredEntries` returns `[]`. |

### Step 2: Implement HistoryViewModel

- `ViewModels/HistoryViewModel.swift`:
  - `@Observable` class with `modelContext`, `locationFilter: Location?`, `startDate: Date?`, `endDate: Date?`.
  - Computed or refreshed `filteredEntries: [SiteChangeEntry]` that applies both filters and sorts by `startTime` descending.
  - `deleteEntry(_:)` — removes the entry from the context and saves.
  - `updateEntry(_:location:startTime:endTime:note:)` — mutates fields and saves.
- Run tests — all 17 tests must pass before proceeding to UI.

### Step 3: Implement Views

1. **History list UI** (Spec section 3.3.2)
   - `Views/HistoryView.swift`:
     - `List` displaying `filteredEntries`.
     - Each row shows: location `displayName`, start date/time, duration or "Active", note preview.
     - Filter controls: location picker ("All" + all locations), date range picker ("Last 7 days", "Last 30 days", "Last 90 days", "All Time").
     - Swipe-to-delete with confirmation.
     - Tap on entry navigates to edit view.

2. **History entry edit view**
   - `Views/HistoryEditView.swift`:
     - `Picker` for location, `DatePicker` for start/end time, `TextField` for note.
     - Save and Cancel buttons.

### Files Created/Modified
- `SiteCycleTests/HistoryViewModelTests.swift` (new — write first)
- `SiteCycle/ViewModels/HistoryViewModel.swift` (new)
- `SiteCycle/Views/HistoryView.swift` (new, replaces placeholder)
- `SiteCycle/Views/HistoryEditView.swift` (new)

### Verification
- All 17 `HistoryViewModelTests` pass.
- History tab shows all logged site changes in reverse chronological order.
- Filtering by location works -- only entries for selected location appear.
- Filtering by date range works -- "Last 7 days", "Last 30 days", etc.
- Editing an entry changes persisted values.
- Deleting an entry removes it from the list and from persistence.
- Active entry (no end time) shows "Active" instead of duration.

---

## Phase 5: Statistics & Charts

**Goal:** Build the statistics tab with per-location analytics, absorption insights, usage distribution chart, and rotation timeline.

### Prerequisites
- Phase 4 complete (history entries exist and are browsable).

### Step 1: Write Tests (before implementation)

Create `SiteCycleTests/StatisticsViewModelTests.swift`. The statistics logic is computationally dense and benefits greatly from TDD — write all calculation tests first so the ViewModel can be built against a precise contract.

The ViewModel exposes a `LocationStats` struct (or similar) per location and aggregate computation methods. Tests should exercise pure computation logic wherever possible. Use the same `makeContainer()` helper pattern.

#### Per-Location: Total Uses

| Test name | What it validates |
|-----------|-------------------|
| `totalUsesCountsAllEntriesForLocation` | Location with 4 entries (3 completed + 1 active) → `totalUses == 4`. |
| `totalUsesIsZeroForNeverUsedLocation` | Location with no entries → `totalUses == 0`. |

#### Per-Location: Average Duration

| Test name | What it validates |
|-----------|-------------------|
| `averageDurationComputesMeanOfCompletedEntries` | 3 completed entries with durations 48, 72, 96 → `averageDuration == 72.0`. |
| `averageDurationExcludesActiveEntries` | 2 completed entries + 1 active → average computed from the 2 completed only. |
| `averageDurationIsNilWhenNoCompletedEntries` | 1 active entry, 0 completed → `averageDuration == nil`. |

#### Per-Location: Median Duration

| Test name | What it validates |
|-----------|-------------------|
| `medianDurationReturnsMiddleValueForOddCount` | Durations [48, 72, 96] → `medianDuration == 72.0`. |
| `medianDurationReturnsAverageOfMiddleTwoForEvenCount` | Durations [48, 60, 72, 96] → `medianDuration == 66.0`. |
| `medianDurationIsNilWhenNoCompletedEntries` | No completed entries → `medianDuration == nil`. |
| `medianDurationWithSingleEntry` | One completed entry (72h) → `medianDuration == 72.0`. |

#### Per-Location: Min/Max Duration

| Test name | What it validates |
|-----------|-------------------|
| `minMaxDurationReturnsCorrectRange` | Durations [48, 72, 96] → `minDuration == 48.0`, `maxDuration == 96.0`. |
| `minMaxDurationWithSingleEntry` | One entry (72h) → `min == max == 72.0`. |
| `minMaxDurationIsNilWhenNoCompletedEntries` | No completed entries → both nil. |

#### Per-Location: Last Used & Days Since

| Test name | What it validates |
|-----------|-------------------|
| `lastUsedReturnsNewestStartTime` | 3 entries → `lastUsed` matches the entry with the most recent `startTime`. |
| `lastUsedIsNilForNeverUsedLocation` | No entries → `lastUsed == nil`. |
| `daysSinceLastUseCalculatesCorrectly` | Entry with `startTime` 10 days ago → `daysSinceLastUse == 10`. |
| `daysSinceLastUseIsNilForNeverUsedLocation` | No entries → `daysSinceLastUse == nil`. |

#### Overall Average

| Test name | What it validates |
|-----------|-------------------|
| `overallAverageDurationAcrossAllLocations` | Entries across 3 locations with various durations → overall average is mean of all completed durations. |
| `overallAverageIsNilWhenNoCompletedEntries` | Only active entries → overall average is nil. |

#### Absorption Insight (Spec section 3.4.2)

| Test name | What it validates |
|-----------|-------------------|
| `absorptionFlagTriggeredWhenBelowThreshold` | Overall avg 72h, location avg 55h, threshold 20% (cutoff 57.6h). 55 < 57.6 → flagged. |
| `absorptionFlagNotTriggeredWhenAboveThreshold` | Overall avg 72h, location avg 65h, threshold 20%. 65 > 57.6 → not flagged. |
| `absorptionFlagNotTriggeredAtExactThreshold` | Location avg exactly at the cutoff → not flagged (must be *below*, not equal). |
| `absorptionFlagCustomThreshold` | Threshold set to 10% instead of 20%. Verify the cutoff adjusts (72 * 0.9 = 64.8). |
| `absorptionFlagMessageIncludesPercentage` | Flagged location's message contains the correct percentage below average (e.g., "24% below"). |
| `absorptionFlagSkipsLocationsWithNoCompletedEntries` | Location with only active entries → not flagged (no average to compare). |

#### Usage Distribution Data

| Test name | What it validates |
|-----------|-------------------|
| `usageDistributionReturnsCorrectCounts` | 3 locations with 5, 3, 1 entries respectively → distribution data matches those counts. |
| `usageDistributionExcludesLocationsWithZeroUses` | Never-used enabled location → omitted from distribution (or included with count 0 — pick a convention and test it). |

#### Edge Cases

| Test name | What it validates |
|-----------|-------------------|
| `statisticsWithNoDataReturnsEmpty` | No entries at all → all per-location stats arrays are empty, no crash. |
| `statisticsWithSingleCompletedEntry` | One entry → totalUses 1, avg/median/min/max all equal its duration. |

### Step 2: Implement StatisticsViewModel

- `ViewModels/StatisticsViewModel.swift`:
  - `@Observable` class with `modelContext`, `absorptionThreshold: Int` (from `@AppStorage`, default 20).
  - `LocationStats` struct: `location: Location`, `totalUses: Int`, `averageDuration: Double?`, `medianDuration: Double?`, `minDuration: Double?`, `maxDuration: Double?`, `lastUsed: Date?`, `daysSinceLastUse: Int?`, `absorptionFlag: String?`.
  - `locationStats: [LocationStats]` — computed for all enabled locations.
  - `overallAverageDuration: Double?` — mean of all completed entries.
  - `usageDistribution: [(locationName: String, count: Int)]` — for chart data.
  - `timelineEntries(days:) -> [(entry: SiteChangeEntry, locationName: String)]` — for rotation timeline.
  - Make statistical computations pure functions (e.g., `static func computeMedian(_ values: [Double]) -> Double?`) for easy testing.
- Run tests — all 27 tests must pass before proceeding to UI.

### Step 3: Implement Views

1. **Statistics main view** (Spec section 3.4)
   - `Views/StatisticsView.swift`:
     - **Usage Distribution Chart** (Swift Charts `BarMark`).
     - **Per-Location Stats** list/grid with absorption flag warnings.
     - **Rotation Timeline** with 30/60/90 day segmented control.
     - **Empty state** when no completed entries exist.

### Files Created/Modified
- `SiteCycleTests/StatisticsViewModelTests.swift` (new — write first)
- `SiteCycle/ViewModels/StatisticsViewModel.swift` (new)
- `SiteCycle/Views/StatisticsView.swift` (new, replaces placeholder)

### Verification
- All 27 `StatisticsViewModelTests` pass.
- Statistics tab shows usage distribution chart with correct counts per location.
- Per-location stats display all required metrics (total uses, avg, median, min, max, last used, days since).
- Absorption flags appear on locations meeting the threshold criteria.
- Rotation timeline shows colored blocks for site sessions over the selected time range.
- Empty state displays when no data exists.

---

## Phase 6: Settings Completion, CSV Export & Polish

**Goal:** Complete the settings screen, implement CSV export, add the sync status indicator, and polish accessibility and Dark Mode support.

### Prerequisites
- Phase 5 complete (all main features functional).

### Step 1: Write Tests (before implementation)

Create `SiteCycleTests/CSVExporterTests.swift`. CSV generation is pure data transformation — ideal for thorough unit testing. The exporter should be a struct/class with a static or instance method like `CSVExporter.generate(from: [SiteChangeEntry]) -> String` that can be tested without any UI involvement.

#### CSV Format & Headers

| Test name | What it validates |
|-----------|-------------------|
| `csvHeaderRowIsCorrect` | Output starts with `"date,location,duration_hours,note\n"`. |
| `csvEmptyDataProducesHeaderOnly` | No entries → output is exactly the header row. |

#### Field Formatting

| Test name | What it validates |
|-----------|-------------------|
| `csvDateIsISO8601Formatted` | Entry's `startTime` appears as ISO 8601 string (e.g., `"2026-02-07T15:30:00Z"`). |
| `csvLocationUsesDisplayName` | Entry for "Left Front Abdomen" → `location` column contains `"Left Front Abdomen"`. |
| `csvDurationRoundedToOneDecimal` | Entry with 68.4667 hours → `duration_hours` column contains `"68.5"`. |
| `csvActiveEntryHasEmptyDuration` | Entry with `endTime == nil` → `duration_hours` column is empty. |
| `csvNilNoteProducesEmptyField` | Entry with no note → `note` column is empty. |

#### CSV Escaping (RFC 4180 compliance)

| Test name | What it validates |
|-----------|-------------------|
| `csvNoteWithCommasIsQuotedCorrectly` | Note `"sore, red area"` → field wrapped in double quotes: `"\"sore, red area\""`. |
| `csvNoteWithDoubleQuotesIsEscaped` | Note `'said "ouch"'` → quotes doubled and field wrapped: `"\"said \"\"ouch\"\"\""`. |
| `csvNoteWithNewlinesIsQuoted` | Note with `\n` → field wrapped in double quotes. |
| `csvLocationNameWithCommaIsQuoted` | Custom location named `"Hip, Left"` → properly quoted. |

#### Ordering & Multiple Entries

| Test name | What it validates |
|-----------|-------------------|
| `csvEntriesInChronologicalOrder` | 3 entries → rows appear oldest-first (ascending `startTime`). |
| `csvMultipleEntriesProduceCorrectRowCount` | 5 entries → 6 lines total (1 header + 5 data rows). |

#### File Naming

| Test name | What it validates |
|-----------|-------------------|
| `csvFileNameIncludesTodaysDate` | `CSVExporter.fileName()` returns `"sitecycle-export-YYYY-MM-DD.csv"` with today's date. |

### Step 2: Implement CSVExporter

- `Utilities/CSVExporter.swift`:
  - `struct CSVExporter` with:
    - `static func generate(from entries: [SiteChangeEntry]) -> String`
    - `static func fileName(for date: Date = Date()) -> String`
  - Proper RFC 4180 escaping for fields containing commas, quotes, or newlines.
  - ISO 8601 date formatting, 1-decimal duration rounding.
- Run tests — all 14 `CSVExporterTests` must pass before wiring into the UI.

### Step 3: Implement Settings & Polish

1. **Settings completion** (Spec section 7)
   - Wire up "Export Data" row: use `ShareLink` with the generated CSV data and filename.
   - Ensure "Target Duration" and "Absorption Alert Threshold" values are read by HomeViewModel and StatisticsViewModel.

2. **Sync status indicator** (Spec section 6.2)
   - Small cloud icon in nav bar. Simple approach: `NWPathMonitor` for connectivity status.
   - States: synced (cloud checkmark), offline (cloud with slash).

3. **Dark Mode verification**
   - Review all views for semantic colors. Fix hardcoded colors.

4. **Dynamic Type verification** (Spec section 5.4)
   - Ensure all text uses dynamic type styles. Fix layout at largest sizes.

5. **Edge case handling & polish**
   - Empty states on all screens.
   - Prevent disabling all locations (require at least 1 enabled).
   - Prevent duplicate site changes from rapid double-tap.
   - Long note truncation in history list.

### Files Created/Modified
- `SiteCycleTests/CSVExporterTests.swift` (new — write first)
- `SiteCycle/Utilities/CSVExporter.swift` (new)
- `SiteCycle/Views/SettingsView.swift` (updated)
- `SiteCycle/Views/ContentView.swift` (sync indicator)
- Various view files (Dark Mode / Dynamic Type fixes as needed)

### Verification
- All 14 `CSVExporterTests` pass.
- Export produces a valid CSV file with correct headers and data.
- Sharing the CSV file works via the share sheet.
- Settings values (target duration, threshold) are reflected in Home and Statistics screens.
- App looks correct in both Light and Dark Mode.
- App is usable at all Dynamic Type sizes without layout breakage.
- All empty states render correctly.
- No crashes when data is missing or locations are deleted.

---

## Phase 7: GitHub Actions CI/CD & TestFlight Deployment

**Goal:** Set up a GitHub Actions workflow that builds the app on every push/PR, and a release workflow that archives, signs, and uploads the app to TestFlight via App Store Connect.

**Status:** CI workflow and existing unit tests are already implemented. Remaining: TestFlight deployment workflow.

### Prerequisites
- Phase 6 complete (app is feature-complete and polished).
- An Apple Developer account with App Store Connect access.
- The app's Bundle Identifier registered in App Store Connect.

### Test Considerations

Phase 7 has no new ViewModel or business logic requiring unit tests. The CI workflow itself *is* the test infrastructure — it validates that all tests from phases 1–6 pass on every push.

However, before finalizing this phase, verify:
- **All test files are registered** in `project.pbxproj` (PBXFileReference, PBXGroup, PBXSourcesBuildPhase).
- **CI runs all tests**: the `xcodebuild test` step in `ci.yml` executes the full `SiteCycleTests` target.
- **Test count audit**: confirm the expected test count matches CI output. Expected totals after all phases:
  - `LocationTests` — 6
  - `SiteChangeEntryTests` — 7
  - `DefaultLocationsTests` — 8
  - `LocationConfigTests` — 15
  - `HomeViewModelTests` — 9
  - `SiteChangeViewModelTests` — 20
  - `HistoryViewModelTests` — 17 (Phase 4)
  - `StatisticsViewModelTests` — 27 (Phase 5)
  - `CSVExporterTests` — 14 (Phase 6)
  - **Total: 123 tests**

### Deliverables

1. **CI workflow -- build & test on every push** (`.github/workflows/ci.yml`) — **already implemented**
   - Trigger: `push` to any branch, `pull_request` to `main`.
   - Runner: `macos-15` (Xcode 16+).
   - Steps: checkout, select Xcode, build, run tests, SwiftLint.

2. **TestFlight release workflow** (`.github/workflows/testflight.yml`)
   - Trigger: `push` of a tag matching `v*` (e.g., `v1.0.0`), or manual `workflow_dispatch`.
   - Runner: `macos-15`.
   - Steps:
     - **Check out code.**
     - **Install the Apple certificate and provisioning profile:**
       - Use a keychain-based approach: decode a base64-encoded `.p12` distribution certificate and provisioning profile from GitHub Secrets, import into a temporary keychain.
       - Required secrets:
         - `APPLE_CERTIFICATE_BASE64` -- base64-encoded `.p12` distribution certificate.
         - `APPLE_CERTIFICATE_PASSWORD` -- password for the `.p12` file.
         - `APPLE_PROVISIONING_PROFILE_BASE64` -- base64-encoded `.mobileprovision` file.
         - `APPSTORE_CONNECT_API_KEY_ID` -- App Store Connect API key ID.
         - `APPSTORE_CONNECT_API_ISSUER_ID` -- App Store Connect API issuer ID.
         - `APPSTORE_CONNECT_API_KEY_BASE64` -- base64-encoded `.p8` private key.
       - Script to decode and install:
         ```
         # Create temporary keychain
         security create-keychain -p "" build.keychain
         security default-keychain -s build.keychain
         security unlock-keychain -p "" build.keychain
         # Import certificate
         echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > cert.p12
         security import cert.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
         security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
         # Install provisioning profile
         echo "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 --decode > profile.mobileprovision
         mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
         cp profile.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/
         ```
     - **Archive the app:**
       ```
       xcodebuild archive \
         -scheme SiteCycle \
         -archivePath $RUNNER_TEMP/SiteCycle.xcarchive \
         -destination 'generic/platform=iOS' \
         CODE_SIGN_STYLE=Manual \
         PROVISIONING_PROFILE_SPECIFIER="..." \
         CODE_SIGN_IDENTITY="Apple Distribution"
       ```
     - **Export the IPA:**
       - Create an `ExportOptions.plist` specifying `app-store` distribution method, team ID, and provisioning profile mapping.
       ```
       xcodebuild -exportArchive \
         -archivePath $RUNNER_TEMP/SiteCycle.xcarchive \
         -exportPath $RUNNER_TEMP/export \
         -exportOptionsPlist ExportOptions.plist
       ```
     - **Upload to TestFlight:**
       - Use `xcrun altool` or (preferred) `xcrun notarytool` / the App Store Connect API:
       ```
       xcrun altool --upload-app \
         -f $RUNNER_TEMP/export/SiteCycle.ipa \
         --apiKey "$APPSTORE_CONNECT_API_KEY_ID" \
         --apiIssuer "$APPSTORE_CONNECT_API_ISSUER_ID" \
         --type ios
       ```
       - Alternatively, use the `apple-actions/upload-testflight-build` GitHub Action if available.
     - **Cleanup:** Delete temporary keychain and provisioning profile.

3. **ExportOptions.plist**
   - Committed to the repo at the project root.
   - Contents:
     - `method`: `app-store`
     - `teamID`: your Apple Developer Team ID (can be templated/parameterized via secret).
     - `provisioningProfiles`: dictionary mapping bundle ID to profile name.
     - `signingCertificate`: `Apple Distribution`
     - `uploadBitcode`: `false`
     - `uploadSymbols`: `true`

4. **Documentation**
   - Add a "CI/CD" section to the project README (or a `CI.md` file) documenting:
     - How to set up the required GitHub Secrets (step-by-step for each secret).
     - How to trigger a TestFlight build (push a tag or use workflow_dispatch).
     - How to generate the App Store Connect API key from App Store Connect > Users and Access > Keys.
     - How to export the distribution certificate and provisioning profile as base64.

### Files Created/Modified
- `.github/workflows/ci.yml` (already exists)
- `.github/workflows/testflight.yml` (new)
- `ExportOptions.plist` (new)
- `CI.md` or README update (new/updated)

### Verification
- CI workflow runs all 123 tests on every push and they all pass.
- Push to a branch triggers the CI workflow; it checks out, builds, and passes.
- Creating a tag `v1.0.0-beta.1` triggers the TestFlight workflow.
- With valid secrets configured, the workflow archives, exports, and uploads the IPA to App Store Connect.
- The build appears in TestFlight within App Store Connect after processing.

### Required GitHub Secrets Summary

| Secret Name                          | Description                                      |
|--------------------------------------|--------------------------------------------------|
| `APPLE_CERTIFICATE_BASE64`          | Base64 `.p12` distribution certificate           |
| `APPLE_CERTIFICATE_PASSWORD`        | Password for the `.p12` file                     |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 `.mobileprovision` file                   |
| `APPSTORE_CONNECT_API_KEY_ID`       | App Store Connect API key ID                     |
| `APPSTORE_CONNECT_API_ISSUER_ID`    | App Store Connect API issuer ID                  |
| `APPSTORE_CONNECT_API_KEY_BASE64`   | Base64 `.p8` API private key                     |

---

## Phase Summary

| Phase | Focus                              | Tests First | Test File(s)                   | Test Count | Key Implementation Files                               |
|-------|------------------------------------|----|-------------------------------|------------|--------------------------------------------------------|
| 1     | Project scaffold & data models     | — (retroactive) | LocationTests, SiteChangeEntryTests, DefaultLocationsTests | 21 | Models, DefaultLocations, ContentView, App entry point |
| 2     | Location config & onboarding       | — (retroactive) | LocationConfigTests           | 15 | LocationConfigView, SettingsView, OnboardingView       |
| 3     | Home screen & site change logging  | — (retroactive) | HomeViewModelTests, SiteChangeViewModelTests | 29 | HomeView, SiteSelectionSheet, ViewModels               |
| 4     | History view                       | **Yes** | HistoryViewModelTests         | 17 | HistoryView, HistoryEditView, HistoryViewModel         |
| 5     | Statistics & charts                | **Yes** | StatisticsViewModelTests      | 27 | StatisticsView, StatisticsViewModel                    |
| 6     | CSV export, settings, polish       | **Yes** | CSVExporterTests              | 14 | CSVExporter, SettingsView, Dark Mode & accessibility    |
| 7     | CI/CD & TestFlight deployment      | Audit | (all of the above)            | 123 total | GitHub Actions workflows, ExportOptions.plist           |

### TDD Workflow for Phases 4–6

Each phase follows a strict test-driven cycle:

1. **Write tests first** — Create the test file with all test functions. Tests will not compile initially (the ViewModel/utility doesn't exist yet).
2. **Create minimal stubs** — Add just enough code (empty struct/class, method signatures returning placeholder values) to make the tests compile.
3. **Run tests — expect failures** — All tests should compile and run, but most should fail (red).
4. **Implement** — Build out the real logic method by method, running tests after each change.
5. **All tests green** — Every test passes before moving to the View layer.
6. **Build views** — Implement the SwiftUI views that consume the now-tested ViewModel.
7. **Final CI check** — Push and confirm CI passes with the full test suite.

Each phase produces a buildable, testable increment. Phase 1 must be completed first. Phases 2-5 each depend on the prior phase. Phase 6 depends on all previous phases. Phase 7 can be done in parallel with Phases 2-6 (only the TestFlight upload requires a working build).
