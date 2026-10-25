# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SiteCycle is an iOS app for insulin pump users to track infusion site rotation. It recommends optimal pump site placement based on usage history to prevent lipohypertrophy and scarring. The app is pump-agnostic and requires no user account.

## Tech Stack

- **Language:** Swift 6.0, targeting iOS 18.0+ and watchOS 11.0+
- **UI:** SwiftUI
- **Persistence:** SwiftData with CloudKit sync (container: `iCloud.com.sitecycle.app`)
- **Charts:** Swift Charts framework (for statistics views)
- **Architecture:** MVVM — Models/, ViewModels/, Views/, Utilities/
- **Watch App:** Companion watchOS app with WidgetKit complications
- **No external dependencies** — uses only Apple frameworks

## Build Commands

This is an Xcode project (no SPM Package.swift at the root). Build and test via `xcodebuild`:

```bash
# Build iOS app for Simulator (requires Xcode 26)
xcodebuild build -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'

# Build Watch app for Simulator
xcodebuild build -scheme SiteCycleWatch -project SiteCycle.xcodeproj -destination 'generic/platform=watchOS Simulator'

# Run tests (iOS only)
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'

# CI builds (no code signing)
xcodebuild build-for-testing \
  -scheme SiteCycle -project SiteCycle.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

## Architecture

### Data Models (SwiftData)

Three `@Model` classes in `Models/`:

- **Location** — body location for site placement. Fields: `id`, `zone`, `side` (optional "left"/"right"), `isEnabled`, `isCustom`, `sortOrder`. Has a computed `displayName` (e.g., "Left Front Abdomen"). One-to-many relationship with `SiteChangeEntry` (delete rule: nullify).
- **SiteChangeEntry** — a single site change event. Fields: `id`, `startTime`, `endTime` (nil if active), `note`, `location` (relationship), `problems` (many-to-many with `SiteProblem` — why the site ended early; several can apply, empty means none). `safeProblems` returns them sorted by `sortOrder`; `hasProblems`. Computed `durationHours`.
- **SiteProblem** — a reason for an early site change. Fields: `id`, `name`, `emoji`, `isEnabled`, `isCustom`, `sortOrder`, `defaultKey` (stable key for seeded defaults, nil for custom). Many-to-many with `SiteChangeEntry` via `entries` (delete rule: nullify).

### App Initialization

`SiteCycleApp.swift` configures the `ModelContainer` with CloudKit (`.automatic` mode) and falls back to local-only storage (`.none`) if CloudKit is unavailable (e.g., CI without code signing entitlements). Seeds 14 default locations (7 zones x left/right) on first launch via `seedDefaultLocations()` in `Utilities/DefaultLocations.swift`. Seeds default problems via `seedDefaultProblems()` in `Utilities/DefaultProblems.swift` (inserts any default whose `defaultKey` is missing, so a new default added in a later version reaches existing users), then `deduplicateProblems()` merges defaults sharing a `defaultKey` and custom problems sharing a `SiteProblem.nameKey` (both created when two devices act before CloudKit syncs). Every dedup keeper must be identical on every device — otherwise two devices deduplicating before syncing can each delete the copy the other kept — so keepers are picked from synced record properties only, never fetch order or entry counts: for problems, a customized default (renamed, new emoji, disabled, or moved from its seeded index) first, then for custom problems an enabled one, then lowest `id`; for entries, lowest `id`. `deduplicateSiteChangeEntries()` merges a duplicate's `problems` into the keeper's.

Onboarding state is tracked via `@AppStorage("hasCompletedOnboarding")`.

### Navigation Structure

Tab-based: Home, History, Statistics. Settings is accessible via a gear icon in the navigation bar. Site change logging is presented as a modal sheet from the Home tab.

### Recommendation Engine (core logic)

The site selection sheet shows two sections — **Recommended** and **All Locations**:
- **Recommended section:** depends on the `RecommendationStrategy` setting (`@AppStorage("recommendationStrategy")`, default `bySite`):
  - **By Site** (default): 3 least recently used / never-used locations (most recovery time)
  - **By Body Part:** locations are grouped by (bodyPart, side); the 3 least recently used groups are chosen (group recency = most recent use across its sites; never-used groups sort as oldest), and the least recently used site within each group is recommended (never-used sites first, ties by lowest `sortOrder`). The point of this mode is to give an entire body part a cooling-off period between uses even when the specific sites differ — e.g. it prevents "L Thigh (Front)" being used immediately after "L Thigh (Side)", which by-site rotation would allow
  - **Body Part Cooldown:** per-site least-recently-used, but any site whose (bodyPart, side) group was used within the last N site changes (`@AppStorage("bodyPartCooldownCount")`, default 2, range 1–10; the Settings stepper is only visible in this mode) sorts below all sites from groups that were not. Hot sites are deprioritized, never excluded, so recommendations never go empty; when every group is hot the ordering degrades gracefully to By Site. Note: a never-used site in a hot group sorts below used sites from cool groups (the partition dominates the never-used-first rule). Rationale: By Body Part rotates groups evenly, so a body part with 1 site gets used 3x as often per-site as one with 3 sites; cooldown keeps the rest period without that per-site overuse
- **All Locations section:** Every enabled location sorted by most-recent-use, with inline badges — orange warning for the 3 most recently used (avoid), green checkmark for recommended
- The avoid list is always site-based (3 most recently used individual sites) in all strategies; avoid and recommended never overlap
- Never-used locations sort as oldest (always recommended until used)
- `SiteChangeViewModel.computeRecommendations(locations:strategy:cooldownCount:)` is a pure static function; callers (`refresh()`, `PhoneConnectivityManager.buildWatchAppState`) read the settings from UserDefaults via `RecommendationStrategy.load()` / `RecommendationStrategy.loadCooldownCount()`

### Site Problems (early change reasons)

- Defaults (`DefaultProblems.all`): Painful 🤕, Leaking 💧, Fell Off / Ripped Off 🩹, Occlusion 🚫, Unexplained Highs 📈, Bleeding 🩸. Never change a default's `key` — it is persisted.
- Users manage them in Settings → Manage Problems (`ProblemConfigView`): rename, change emoji, enable/disable, reorder, add custom. Defaults can be disabled but never deleted (so seeding never re-adds them); custom problems with history are soft-deleted (`isEnabled = false`), without history hard-deleted — same rule as locations. Names are validated by `SiteProblem.nameError`: non-empty, unique case-insensitively, and free of `;` (`SiteProblem.csvSeparator`), because CSV identifies problems by name. Emoji input goes through `SiteProblem.sanitizeEmoji` (keeps the last emoji character, drops anything else); an empty emoji displays `SiteProblem.fallbackEmoji`.
- Picked with `ProblemChips` (one-tap multi-select chip grid, shared by `SiteChangeConfirmationSheet` and `HistoryEditView`); it shows enabled problems plus the entry's original ones even if disabled.
- **Confirmation sheet:** the "Closing" section (closing site, "31h of 72h", chips, note on that site) comes right after Time, before the new site's note. When the closing site lasted under 75% of the target duration (`EarlyChange.isEarly`), the header reads "Closing · Changed Early?" and the chips are shown; otherwise they're behind a "Record a Problem" button so routine changes stay fast. Problems and note go to `logSiteChange(previousProblems:previousEntry:)` and apply to the `previousEntry` the sheet showed, not whatever is active at confirm time (a watch command may have logged a change meanwhile). The sheet sends `.replace` only for values the user actually edited, and `logSiteChange` writes only differing values and skips an entry deleted while the sheet was open, so confirming never clobbers an edit synced from another device. Once the chip grid has been shown it stays shown for the life of the sheet. Durations on the sheet and in History use `DurationFormat.hoursMinutes` ("31h 24m"); Statistics keeps one decimal ("31.4h") for aggregates.
- **History:** rows show all problem emojis; `HistoryEditView` edits them (`HistoryViewModel.setProblems`); a Problem filter (`HistoryProblemFilter`: all / any problem / a specific problem) sits with the location and date filters.
- **Statistics:** a Problems section (`StatisticsViewModel.summarizeProblems`) shows the any-problem rate and per-problem counts over the time window. A site with several problems counts once toward "any" and once toward each. The denominator is completed sites plus an active site only if it already has a problem. Each location's stats carry the same `ProblemSummary` and show a rate plus per-type breakdown ("Problems: 3 of 9 · 33%  💧2 🤕1") — a rate, because locations are used different numbers of times.
- CSV export adds a trailing `problems` column (names joined by `;`) only when some entry has a problem, so problem-free exports still import into older app versions. Import accepts headers with or without it (column 5 is only read when the header declares `problems`), keeps existing problems (they are configuration, not history), matches names case-insensitively, and creates unknown names as custom problems.

### Statistics Time Window & Duration Percentile

- The Statistics tab has a segmented time-window filter (All / 9mo / 3mo / 1mo / 14d, `StatsTimeWindow`, persisted in `@AppStorage("statisticsTimeWindow")`). Entries count when their `startTime` is in the window. Counts, durations, usage distribution and absorption flags respect the window; last-used / site rest time always use full history.
- Duration stats (median and percentile) **always skip the active site** (no `endTime`) and run through `filterAnomalies` first. `StatisticsViewModel.summarize(_:)` / `completedDurations(of:since:)` are the shared static helpers.
- The percentile is **P25** (`StatisticsViewModel.durationPercentile`): with site changes every ~1.5–3 days, a 14-day window has only ~5–9 sites, so a tail percentile like P10 collapses to the minimum while P25 stays stable ("1 in 4 sites ended before X" = how often sites fail early). It's omitted below 4 samples.
- Home shows a small `QuickStatBadge` at the top-right of the progress ring: median or P25 (`@AppStorage("homeStatMetric")`) over a window (`@AppStorage("homeStatTimeWindow")`, default 1mo), configured in Settings → Home Screen Stat. Computed by `HomeViewModel.refreshQuickStat()` with the same helpers so it matches the Statistics tab.

## CI / CD

**Active CI is a mix of Xcode Cloud and one GitHub Actions workflow:**

- Xcode Cloud handles build/test/publish via two workflows: **"CI"** (unit tests, watch build, and a signing-verification archive — all as parallel actions in one workflow, triggered on every PR to `main`) and **"TestFlight"** (archive + upload plus the single UI smoke test, both manually startable and automatic on `main` changes). See [`docs/xcode-cloud-setup.md`](docs/xcode-cloud-setup.md) for the full configuration.
- `.github/workflows/lint.yml` — runs SwiftLint `--strict` on PRs to `main` (paths-ignored for docs/images/`*.py`, same filter as the disabled `ci.yml` had). Kept on GitHub Actions deliberately: **Xcode Cloud has no built-in linting step**, and lint enforcement on every PR matters enough not to drop it during the migration. The `.swiftlint.yml` `included:` list already covers `SiteCycleWidgets/` alongside the existing target directories.

The GitHub Actions workflows below are **disabled** (`gh workflow disable`, not removed — kept in the repo and documented here for reference/rollback), now that Xcode Cloud covers what they did:

- `.github/workflows/ci.yml` — ran on every push and PR. Jobs (SwiftLint has since moved to `lint.yml` above and was removed from this file):
  1. **Build & Test** — builds on `macos-15`, auto-selects the latest Xcode 26 and an available iPhone simulator, builds with code signing disabled, and runs all unit tests (`SiteCycleTests`).
  2. **Build Watch App** — builds the `SiteCycleWatch` scheme for the watchOS Simulator with code signing disabled.
  3. **Archive (TestFlight dry run)** — see `docs/testflight-setup.md`.
- `.github/workflows/ui-tests.yml` — ran on PRs only, **paths-filtered** to app / UI-test / project-file / workflow changes, so docs-only PRs didn't burn CI minutes. Ran the `SiteCycleUITests` target serially on a single simulator; its non-obvious xcodebuild flags (`-parallel-testing-enabled NO`, `-disable-concurrent-destination-testing`, redirecting output before `xcpretty`) are worth keeping if it is ever re-enabled.
- `.github/workflows/testflight.yml` — see `docs/testflight-setup.md`.

Key CI considerations (apply to both the disabled GitHub Actions workflows and their Xcode Cloud equivalents, since Xcode Cloud's Automatic signing runs full builds — no signing bypass needed there):
- The GitHub Actions workflows disabled code signing (`CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`), so CloudKit entitlements were absent there. Both the iOS and Watch app's `ModelContainer` init have a fallback from `.automatic` to `.none` to handle this — **do not remove the fallbacks**, since Xcode Cloud's non-Archive (Test/Build) actions don't sign either.
- The test target (`SiteCycleTests`) is **hosted by the app** (`TEST_HOST` is set in the Xcode project). The app must launch successfully for tests to run.

## Testing

### Unit tests (`SiteCycleTests/`)

Tests are in `SiteCycleTests/` using the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`, `#require`).

#### Writing tests — important patterns

- **Swift Testing `throws` requirement:** Any test function using `try #require(...)` must be marked `throws`. Omitting it causes a compilation error.
- **SwiftData in tests:** Tests that need a `ModelContainer` should create an in-memory container with CloudKit disabled:
  ```swift
  private func makeContainer() throws -> ModelContainer {
      let schema = Schema([Location.self, SiteChangeEntry.self])
      let config = ModelConfiguration(
          schema: schema,
          isStoredInMemoryOnly: true,
          cloudKitDatabase: .none
      )
      return try ModelContainer(for: schema, configurations: [config])
  }
  ```
- **Model instantiation without a container:** Simple `Location` and `SiteChangeEntry` objects can be created without a `ModelContainer` for basic property tests. A container is only needed when using `ModelContext` operations (insert, fetch, save).
- **`@MainActor` on test structs:** Test structs that create ViewModels or use `ModelContext` must be annotated with `@MainActor` because the ViewModels and utility functions are `@MainActor`-isolated (Swift 6 strict concurrency).

### UI tests (`SiteCycleUITests/`)

There is deliberately **one** XCUITest smoke test (`SmokeTests.testLogSiteChangesEndToEnd`): log two site changes, check that Home and History update. It covers wiring only (sheets present, confirm saves, `@Query` views refresh). **Do not add UI tests for business logic.** Put the logic in a ViewModel and unit-test it. See `docs/ui-testing.md` for why the broader suite was removed.

- **Launch arguments** (parsed in `SiteCycleApp`): `-uiTestMode` forces in-memory SwiftData + `cloudKitDatabase: .none`; `-completeOnboarding` skips onboarding. `SiteCycleUITestCase` passes both.
- **Page objects:** `HomeScreen`, `SiteSelectionScreen`, `SiteChangeConfirmationScreen`, `HistoryScreen`.
- **Accessibility identifiers** follow `<screen>.<element>` (e.g. `home.allLocations`, `siteSelection.row.<fullDisplayName>`, `history.row.<uuid>`). Keep the existing ones; they also help VoiceOver tooling.
- **Waits:** use `waitForExistence(timeout:)` or `XCTNSPredicateExpectation`, never `Thread.sleep`.
- **Runs in** the Xcode Cloud "TestFlight" workflow (merges to `main`), not on every PR.
- **Known app bug:** the Welcome → Configure transition in `OnboardingView`'s paged `TabView` has crashed the app during UI-test runs. It's an app bug to fix separately, not a testing task.

## SwiftUI Pitfalls

- `.foregroundStyle(.accent)` does not compile — `ShapeStyle` has no `.accent` member. Use `.tint` for accent color styling.
- **`@Observable` needs `import Observation`** — `SwiftData` does NOT re-export the `Observation` framework. ViewModels that use `@Observable` without importing `SwiftUI` must explicitly `import Observation`.
- **Multiple closures:** When a SwiftUI modifier takes 2+ closure arguments (e.g., `.sheet(isPresented:onDismiss:content:)`), use explicit parameter labels for all closures — do NOT use trailing closure syntax.

## SwiftLint Rules (CI-enforced)

SwiftLint runs in CI (`.github/workflows/lint.yml`) with `--strict` mode (all warnings are errors). Key rules:
- `large_tuple`: Tuples may have at most 2 members. Use a struct instead.
- `empty_count` (opt-in, enabled): Use `.isEmpty` instead of `.count == 0`.
- `force_unwrapping`: Never use `!` to force-unwrap. In tests, use `try #require(value)`.
- `multiple_closures_with_trailing_closure`: When passing 2+ closures, use explicit labels for all.
- `function_body_length`: Function bodies must be <=50 lines. Extract helper methods.
- `file_length`: Files must be <=500 lines. Split large files if needed.
- `type_body_length`: Struct/class bodies must be <=300 lines.

## Adding Files to the Xcode Project

When creating a new Swift file, it must be registered in `SiteCycle.xcodeproj/project.pbxproj` in three places:
1. **PBXFileReference** — declares the file
2. **PBXGroup** — adds it to the correct folder group
3. **PBXSourcesBuildPhase** — adds it to the correct target's compile sources (via a PBXBuildFile entry)

Use sequential hex IDs following the existing pattern (e.g., `8A0000000000000000000013` for the file ref, `8A0000000000000000000113` for the build file).

## Swift 6 Concurrency

The project uses Swift 6 language mode with strict concurrency checking:

- **ViewModels** are all `@MainActor`-isolated because they hold a `ModelContext` and drive UI state.
- **Utility functions** that accept `ModelContext` are `@MainActor`.
- **Views** inherit main actor isolation from SwiftUI.
- **Models** — isolation is handled by SwiftData's `@Model` macro.

## Apple Watch App

### Targets

| Target | Bundle ID | Platform |
|--------|-----------|----------|
| `SiteCycleWatch` | `com.sitecycle.app.watchkitapp` | watchOS 11+ |
| `SiteCycleWatchWidgets` | `com.sitecycle.app.watchkitapp.widgets` | watchOS 11+ |
| `SiteCycleWidgets` | `com.sitecycle.app.widgets` | iOS 18+ |

### Shared Files (dual target membership)

Only one source file is compiled into multiple targets:
- `SiteCycle/Connectivity/WatchAppState.swift` — shared `Codable` types (`WatchAppState`, `WatchSiteChangeCommand`, `LocationInfo`, `LocationCategory`) and app group constants. Compiled into iOS, watchOS, watch widget, and iPhone widget extension targets. The `appGroupIdentifier` helper strips `.watchkitapp[.widgets]` and `.widgets` suffixes off the bundle ID so all four targets resolve to `group.<prefix>.app`.

The watch app does **not** include `Location.swift`, `SiteChangeEntry.swift`, `SiteProblem.swift`, `DefaultLocations.swift`, `HomeViewModel.swift`, or `SiteChangeViewModel.swift` — it operates as a thin client.

### Data Sync — Thin Client Architecture

The watch is a **thin client**: the iPhone is the single source of truth. The watch has no `ModelContainer`, no SwiftData, and no CloudKit.

- **Watch → Phone:** `WCSession.transferUserInfo` — guaranteed delivery, queued when phone is unreachable. Sends `WatchSiteChangeCommand`.
- **Phone → Watch:** `WCSession.updateApplicationContext` — latest-wins dictionary. Sends `WatchAppState` (active site, recommendations, all locations, target duration).
- **Complications:** Watch writes received state to app group `UserDefaults` for the widget extension.

Key classes: `PhoneConnectivityManager` (iOS), `WatchConnectivityManager` (watchOS) — both `@MainActor @Observable`, delegate methods dispatch to main actor.

`pushCurrentState()` is called: on session activation, app launch, scene `.active`, after site changes/history edits/location config changes/settings changes/CSV import. The App Group write is **unconditional** (does not depend on WCSession activation) so the iPhone widget receives data even when no Apple Watch is paired. `WidgetCenter.shared.reloadAllTimelines()` is invoked at the same time so widgets refresh promptly after a site change.

### Watch Views

- **WatchHomeView** — current site status with progress ring, elapsed time, "Syncing with iPhone..." empty state when no data received
- **WatchContentView** — horizontal paged `TabView` (`.page`): Home on the left, site picker on the right
- **WatchSiteSelectionView** — recommended-first location list, tap to send command via connectivity manager. The "All Locations" section is shown only when `WatchAppState.showAllLocations` is true — set on the iPhone in Settings → Watch Settings → Show All Locations (`@AppStorage("watchShowAllLocations")`, default on). `WatchAppState` decodes a missing `showAllLocations` key as `true` so older cached/sent state still decodes
- **WatchLocationRow** — compact row using `LocationInfo` (not `Location` model)

### Watch ViewModels

- **WatchHomeViewModel** — reads from `WatchAppState` via `WatchConnectivityManager`. Provides `currentLocationName`, `elapsedHours()`, `progressFraction()`
- **WatchSiteChangeViewModel** — reads recommendations from `WatchAppState`. `logSiteChange()` sends command via connectivity manager

### Complications (WidgetKit)

The `SiteCycleWatchWidgets` extension provides watch face complications:
- **AccessoryRectangular** — location name + elapsed time
- **AccessoryCircular** — progress ring with abbreviated time
- **AccessoryInline** — single line: "L Abdomen (Front) · 2h 15m"

Timeline refreshes every 15 minutes with entries for the next 2 hours.

## iPhone Widgets (`SiteCycleWidgets/`)

The `SiteCycleWidgets` extension provides iPhone widgets that mirror the watch's circular complication. Two families:
- **systemSmall** (Home Screen, 2x2) — full-color heat ring (green/yellow/red) with elapsed hours centered.
- **accessoryCircular** (Lock Screen / StandBy / Smart Stack, 1x1) — tinted ring with abbreviated time.

Reads the same `WatchAppState` from the App Group `UserDefaults` that the watch widget uses; no separate sync path. Tap-to-open is the default `StaticConfiguration` behavior — no `widgetURL` set. The heat color helper (`progressColor(for:)`) is currently duplicated across `HomeView.swift`, the watch app, the watch widget, and the iPhone widget — consolidate into shared code as a follow-up.

**Lock-screen rendering note:** iOS renders `accessoryCircular` in vibrant monochrome on the Lock Screen, so the heat color collapses to the system tint. Full color is preserved on the Home Screen `systemSmall` and StandBy color mode.

## Key Design Decisions

- Settings values (target duration, absorption alert threshold, recommendation strategy, body part cooldown count) use `@AppStorage` (UserDefaults), not SwiftData.
- Logging a new site change automatically closes the previous active entry by setting its `endTime`.
- Soft-delete for locations and custom problems with history (set `isEnabled = false`); hard-delete only if no history exists.
- CloudKit sync is transparent — no account creation, works offline, syncs when connectivity returns.
- Watch app is a thin client — no SwiftData, no CloudKit, no onboarding, no settings, no history editing. Communicates with iPhone via WatchConnectivity.
- Error indicators must always include the technical error details (domain and code) alongside any user-friendly message. Format: append `"\n\nError: <domain> <code>"` to every `.error(...)` state string. This ensures sync failures are diagnosable from screenshots or user reports.
