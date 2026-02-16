# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SiteCycle is an iOS app for insulin pump users to track infusion site rotation. It recommends optimal pump site placement based on usage history to prevent lipohypertrophy and scarring. The app is pump-agnostic and requires no user account.

## Tech Stack

- **Language:** Swift 5.0+, targeting iOS 17.0+
- **UI:** SwiftUI
- **Persistence:** SwiftData with CloudKit sync (container: `iCloud.com.sitecycle.app`)
- **Charts:** Swift Charts framework (for statistics views)
- **Architecture:** MVVM — Models/, ViewModels/, Views/, Utilities/
- **No external dependencies** — uses only Apple frameworks

## Build Commands

This is an Xcode project (no SPM Package.swift at the root). Build and test via `xcodebuild`:

```bash
# Build for iOS Simulator
xcodebuild build -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'

# CI builds (no code signing)
xcodebuild build-for-testing \
  -scheme SiteCycle -project SiteCycle.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

**Linting:** SwiftLint is used in CI (`swiftlint lint --strict`). Not currently installed as a local dev dependency — CI installs via Homebrew. Key rules to watch for:
- `large_tuple`: Tuples may have at most 2 members. Use a struct instead of 3+ member tuples.
- `empty_count` (opt-in, enabled): Use `.isEmpty` instead of `.count == 0`.
- All warnings are errors in `--strict` mode.

## Architecture

### Data Models (SwiftData)

Two `@Model` classes in `Models/`:

- **Location** — body location for site placement. Fields: `id`, `zone`, `side` (optional "left"/"right"), `isEnabled`, `isCustom`, `sortOrder`. Has a computed `displayName` (e.g., "Left Front Abdomen"). One-to-many relationship with `SiteChangeEntry` (delete rule: nullify).
- **SiteChangeEntry** — a single site change event. Fields: `id`, `startTime`, `endTime` (nil if active), `note`, `location` (relationship). Computed `durationHours`.

### App Initialization

`SiteCycleApp.swift` configures the `ModelContainer` with CloudKit (`.automatic` mode) and falls back to local-only storage (`.none`) if CloudKit is unavailable (e.g., CI without code signing entitlements). Seeds 14 default locations (7 zones × left/right) on first launch via `seedDefaultLocations()` in `Utilities/DefaultLocations.swift`.

Onboarding state is tracked via `@AppStorage("hasCompletedOnboarding")`.

### Navigation Structure

Tab-based: Home, History, Statistics. Settings is accessible via a gear icon in the navigation bar. Site change logging is presented as a modal sheet from the Home tab.

### Recommendation Engine (core logic)

The site selection sheet sorts enabled locations by most-recent-use:
- **Avoid list:** 3 most recently used locations (least recovery time)
- **Recommended list:** 3 least recently used / never-used locations (most recovery time)
- Never-used locations sort as oldest (always recommended until used)

## Key Documentation

- **SPEC.md** — Complete product specification. Covers all features (site change logging, location configuration, history, statistics, CSV export), data models, UI/UX design, recommendation logic, acceptance criteria, and out-of-scope items. This is the source of truth for what the app should do.
- **PLAN.md** — Phased implementation roadmap (7 phases). Each phase lists deliverables, files to create/modify, and verification steps. Phases are designed to be completed sequentially in individual sessions.

Always consult SPEC.md for feature requirements and PLAN.md for implementation order and scope when building new phases.

## Implementation Status

**Phases 1–7 are complete.** **Phase 8 (TestFlight deployment) is not yet started** — requires Apple Developer credentials.

| Phase | Focus | Status |
|-------|-------|--------|
| 2 | Location configuration & onboarding | complete |
| 3 | Home screen & site change logging | complete |
| 4 | History view | complete |
| 5 | Statistics & charts | complete |
| 6 | CSV export, settings completion, polish | complete |
| 7 | GitHub Actions CI & test audit | complete |
| 8 | TestFlight deployment | not started |

## CI / GitHub Actions

A CI workflow (`.github/workflows/ci.yml`) runs on every push and PR to `main`:

1. **SwiftLint** — lints all Swift code with `--strict` mode.
2. **Build & Test** — builds on `macos-15`, auto-selects the latest Xcode 16 and an available iPhone simulator, builds with code signing disabled, and runs all tests.

Key CI considerations:
- Code signing is disabled (`CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`), so CloudKit entitlements are absent. The app's `ModelContainer` init has a fallback from `.automatic` to `.none` to handle this — **do not remove the fallback**.
- The test target (`SiteCycleTests`) is **hosted by the app** (`TEST_HOST` is set in the Xcode project). The app must launch successfully for tests to run.

## Testing

Tests are in `SiteCycleTests/` using the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`, `#require`).

### Test files

| File | What it covers |
|------|---------------|
| `LocationTests.swift` | `Location` model: display name formatting, default/custom init, unique IDs |
| `SiteChangeEntryTests.swift` | `SiteChangeEntry` model: `durationHours` computation, default/custom init, unique IDs |
| `DefaultLocationsTests.swift` | `seedDefaultLocations()`: correct count (14), idempotency, zones, sides, sort orders |
| `LocationConfigTests.swift` | Zone CRUD: custom zone creation (with/without laterality), soft/hard delete, toggle, reorder, display names |
| `HomeViewModelTests.swift` | `HomeViewModel`: active site query, elapsed hours, progress fraction, target duration |
| `SiteChangeViewModelTests.swift` | `SiteChangeViewModel`: recommendation engine (avoid/recommended lists, edge cases), logSiteChange, lastUsedDate |
| `HistoryViewModelTests.swift` | `HistoryViewModel`: fetch ordering, location/date filtering, combined filters, entry editing, entry deletion |
| `StatisticsViewModelTests.swift` | `StatisticsViewModel`: total uses, average/median duration per location |
| `StatisticsViewModelDurationTests.swift` | `StatisticsViewModel`: min/max duration, last used, days since last use |
| `StatisticsViewModelAggregateTests.swift` | `StatisticsViewModel`: overall average, absorption insight flags |
| `StatisticsViewModelDistributionTests.swift` | `StatisticsViewModel`: usage distribution, edge cases (empty data, single entry) |
| `CSVExporterTests.swift` | `CSVExporter`: CSV format, headers, field formatting, RFC 4180 escaping, ordering, file naming |

### Writing tests — important patterns

- **Swift Testing `throws` requirement:** Any test function using `try #require(...)` must be marked `throws`. Omitting it causes a compilation error ("errors thrown from here are not handled").
- **SwiftData in tests:** Tests that need a `ModelContainer` should create an in-memory container with CloudKit disabled. See the helper in `DefaultLocationsTests.swift`:
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
- **Model instantiation without a container:** Simple `Location` and `SiteChangeEntry` objects can be created without a `ModelContainer` for basic property/computed-property tests. A container is only needed when using `ModelContext` operations (insert, fetch, save).

## SwiftUI Pitfalls

- `.foregroundStyle(.accent)` does not compile — `ShapeStyle` has no `.accent` member. Use `.tint` for accent color styling (available iOS 15+).
- **`@Observable` needs `import Observation`** — `SwiftData` does NOT re-export the `Observation` framework. ViewModels that use `@Observable` without importing `SwiftUI` must explicitly `import Observation`.
- **Multiple closures:** When a SwiftUI modifier takes 2+ closure arguments (e.g., `.sheet(isPresented:onDismiss:content:)`), use explicit parameter labels for all closures — do NOT use trailing closure syntax. SwiftLint enforces `multiple_closures_with_trailing_closure`.

## SwiftLint Rules (CI-enforced)

Beyond `large_tuple` and `empty_count` (listed above), watch for these in `--strict` mode:
- `force_unwrapping`: Never use `!` to force-unwrap. In tests, use `try #require(value)` instead of `value!`.
- `multiple_closures_with_trailing_closure`: When passing 2+ closures, use explicit labels for all (no trailing closure syntax).
- `function_body_length`: Function bodies must be ≤50 lines (excluding comments/whitespace). Extract helper methods to stay under the limit.
- `file_length`: Files must be ≤500 lines. Split large test files into multiple files if needed.
- `type_body_length`: Struct/class bodies must be ≤300 lines. For test structs, split tests across multiple structs/files by category (e.g., filtering tests vs. edit/delete tests).

## Adding Files to the Xcode Project

When creating a new Swift file, it must be registered in `SiteCycle.xcodeproj/project.pbxproj` in three places:
1. **PBXFileReference** — declares the file
2. **PBXGroup** — adds it to the correct folder group (e.g., `SiteCycleTests`)
3. **PBXSourcesBuildPhase** — adds it to the correct target's compile sources (via a PBXBuildFile entry)

Use sequential hex IDs following the existing pattern (e.g., `8A0000000000000000000013` for the file ref, `8A0000000000000000000113` for the build file).

## Key Design Decisions

- Settings values (target duration, absorption alert threshold) use `@AppStorage` (UserDefaults), not SwiftData.
- Logging a new site change automatically closes the previous active entry by setting its `endTime`.
- Soft-delete for locations with history (set `isEnabled = false`); hard-delete only if no history exists.
- CloudKit sync is transparent — no account creation, works offline, syncs when connectivity returns.
