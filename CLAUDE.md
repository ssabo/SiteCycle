# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SiteCycle is an iOS app for insulin pump users to track infusion site rotation. It recommends optimal pump site placement based on usage history to prevent lipohypertrophy and scarring. The app is pump-agnostic and requires no user account.

## Tech Stack

- **Language:** Swift 6.0, targeting iOS 18.0+
- **UI:** SwiftUI
- **Persistence:** SwiftData with CloudKit sync (container: `iCloud.com.sitecycle.app`)
- **Charts:** Swift Charts framework (for statistics views)
- **Architecture:** MVVM — Models/, ViewModels/, Views/, Utilities/
- **No external dependencies** — uses only Apple frameworks

## Build Commands

This is an Xcode project (no SPM Package.swift at the root). Build and test via `xcodebuild`:

```bash
# Build for iOS Simulator (requires Xcode 16)
xcodebuild build -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
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

1. **SwiftLint** — lints all Swift code with `--strict` mode.
2. **Build & Test** — builds on `macos-15`, auto-selects the latest Xcode 16 and an available iPhone simulator, builds with code signing disabled, and runs all tests.

Key CI considerations:
- Code signing is disabled (`CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`), so CloudKit entitlements are absent. The app's `ModelContainer` init has a fallback from `.automatic` to `.none` to handle this — **do not remove the fallback**.
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

## Key Design Decisions

- Settings values (target duration, absorption alert threshold) use `@AppStorage` (UserDefaults), not SwiftData.
- Logging a new site change automatically closes the previous active entry by setting its `endTime`.
- Soft-delete for locations with history (set `isEnabled = false`); hard-delete only if no history exists.
- CloudKit sync is transparent — no account creation, works offline, syncs when connectivity returns.
