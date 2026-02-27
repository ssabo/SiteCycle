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

Two `@Model` classes in `Models/`:

- **Location** — body location for site placement. Fields: `id`, `zone`, `side` (optional "left"/"right"), `isEnabled`, `isCustom`, `sortOrder`. Has a computed `displayName` (e.g., "Left Front Abdomen"). One-to-many relationship with `SiteChangeEntry` (delete rule: nullify).
- **SiteChangeEntry** — a single site change event. Fields: `id`, `startTime`, `endTime` (nil if active), `note`, `location` (relationship). Computed `durationHours`.

### App Initialization

`SiteCycleApp.swift` configures the `ModelContainer` with CloudKit (`.automatic` mode) and falls back to local-only storage (`.none`) if CloudKit is unavailable (e.g., CI without code signing entitlements). Seeds 14 default locations (7 zones x left/right) on first launch via `seedDefaultLocations()` in `Utilities/DefaultLocations.swift`.

Onboarding state is tracked via `@AppStorage("hasCompletedOnboarding")`.

### Navigation Structure

Tab-based: Home, History, Statistics. Settings is accessible via a gear icon in the navigation bar. Site change logging is presented as a modal sheet from the Home tab.

### Recommendation Engine (core logic)

The site selection sheet shows two sections — **Recommended** and **All Locations**:
- **Recommended section:** 3 least recently used / never-used locations (most recovery time)
- **All Locations section:** Every enabled location sorted by most-recent-use, with inline badges — orange warning for the 3 most recently used (avoid), green checkmark for recommended
- Never-used locations sort as oldest (always recommended until used)

## CI / GitHub Actions

A CI workflow (`.github/workflows/ci.yml`) runs on every push and PR to `main`:

1. **SwiftLint** — lints all Swift code with `--strict` mode (covers `SiteCycle/`, `SiteCycleWatch/`, `SiteCycleWatchWidgets/`).
2. **Build & Test** — builds on `macos-15`, auto-selects the latest Xcode 26 and an available iPhone simulator, builds with code signing disabled, and runs all tests.
3. **Build Watch App** — builds the `SiteCycleWatch` scheme for the watchOS Simulator with code signing disabled.

Key CI considerations:
- Code signing is disabled (`CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`), so CloudKit entitlements are absent. Both the iOS and Watch app's `ModelContainer` init have a fallback from `.automatic` to `.none` to handle this — **do not remove the fallbacks**.
- The test target (`SiteCycleTests`) is **hosted by the app** (`TEST_HOST` is set in the Xcode project). The app must launch successfully for tests to run.

## Testing

Tests are in `SiteCycleTests/` (13 files, 123 tests) using the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`, `#require`).

### Writing tests — important patterns

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

## SwiftUI Pitfalls

- `.foregroundStyle(.accent)` does not compile — `ShapeStyle` has no `.accent` member. Use `.tint` for accent color styling.
- **`@Observable` needs `import Observation`** — `SwiftData` does NOT re-export the `Observation` framework. ViewModels that use `@Observable` without importing `SwiftUI` must explicitly `import Observation`.
- **Multiple closures:** When a SwiftUI modifier takes 2+ closure arguments (e.g., `.sheet(isPresented:onDismiss:content:)`), use explicit parameter labels for all closures — do NOT use trailing closure syntax.

## SwiftLint Rules (CI-enforced)

SwiftLint runs in CI with `--strict` mode (all warnings are errors). Key rules:
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

### Shared Files (dual target membership)

Only one source file is compiled into multiple targets:
- `SiteCycle/Connectivity/WatchAppState.swift` — shared `Codable` types (`WatchAppState`, `WatchSiteChangeCommand`, `LocationInfo`, `LocationCategory`) and app group constants. Compiled into iOS, watchOS, and widget extension targets.

The watch app does **not** include `Location.swift`, `SiteChangeEntry.swift`, `DefaultLocations.swift`, `HomeViewModel.swift`, or `SiteChangeViewModel.swift` — it operates as a thin client.

### Data Sync — Thin Client Architecture

The watch is a **thin client**: the iPhone is the single source of truth. The watch has no `ModelContainer`, no SwiftData, and no CloudKit.

- **Watch → Phone:** `WCSession.transferUserInfo` — guaranteed delivery, queued when phone is unreachable. Sends `WatchSiteChangeCommand`.
- **Phone → Watch:** `WCSession.updateApplicationContext` — latest-wins dictionary. Sends `WatchAppState` (active site, recommendations, all locations, target duration).
- **Complications:** Watch writes received state to app group `UserDefaults` for the widget extension.

Key classes: `PhoneConnectivityManager` (iOS), `WatchConnectivityManager` (watchOS) — both `@MainActor @Observable`, delegate methods dispatch to main actor.

`pushCurrentState()` is called: on session activation, app launch, scene `.active`, after site changes/history edits/location config changes/settings changes/CSV import.

### Watch Views

- **WatchHomeView** — current site status with progress ring, elapsed time, "Syncing with iPhone..." empty state when no data received
- **WatchSiteSelectionView** — recommended-first location list, tap to send command via connectivity manager
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

## Key Design Decisions

- Settings values (target duration, absorption alert threshold) use `@AppStorage` (UserDefaults), not SwiftData.
- Logging a new site change automatically closes the previous active entry by setting its `endTime`.
- Soft-delete for locations with history (set `isEnabled = false`); hard-delete only if no history exists.
- CloudKit sync is transparent — no account creation, works offline, syncs when connectivity returns.
- Watch app is a thin client — no SwiftData, no CloudKit, no onboarding, no settings, no history editing. Communicates with iPhone via WatchConnectivity.
- Error indicators must always include the technical error details (domain and code) alongside any user-friendly message. Format: append `"\n\nError: <domain> <code>"` to every `.error(...)` state string. This ensures sync failures are diagnosable from screenshots or user reports.
