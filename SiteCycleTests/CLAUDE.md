# SiteCycleTests

These are unit tests for the iOS app, written with **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`). They run in Xcode Cloud through the `SiteCycleUnitTests` test plan. The test-quality backlog is in review §4 (`docs/reviews/2026-11-12-adversarial-review.md`).

## Mechanics

- **Register new test files.** Add each one to `project.pbxproj` (target SiteCycleTests, Sources phase `…0310`), following the recipe in the root `CLAUDE.md`. Then run `python3 scripts/check_project.py`.
- **`throws`:** a test that uses `try #require(...)` must be marked `throws`.
- **`@MainActor`:** suites that create ViewModels or use a `ModelContext` must be `@MainActor`.
- **Parameterize:** use `@Test(arguments:)` for table-style cases instead of copy-pasted tests.
- **No force unwrapping.** It's banned by lint; use `try #require(value)`.
- **SwiftData container:** use an in-memory container with CloudKit off, and list **every** model type.

  ```swift
  private func makeContainer() throws -> ModelContainer {
      let schema = Schema([Location.self, SiteChangeEntry.self, SiteProblem.self])
      let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      return try ModelContainer(for: schema, configurations: [config])
  }
  ```

  Each file currently has its own copy of this helper. A shared `TestSupport.swift` is planned (review §4).
- **Plain model objects:** `Location` and `SiteChangeEntry` can be created without a container, which is enough to test pure static functions such as `computeRecommendations` and `summarize`. You need a container only for insert, fetch and save.

## Isolation

Swift Testing runs tests **in parallel**. The app hosts the tests, and it launches normally first, with its on-disk CloudKit store, seeding and WCSession.

- **Use only your own in-memory container.** Never touch the app's store.
- **Never read or write `UserDefaults.standard`.**
  - Use a private suite, and pass it through the code's `load(from:)` parameter:

    ```swift
    let suiteName = "test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    ```

  - Some production code still reads `.standard` internally:
    - `SiteChangeViewModel.refresh()`
    - the default arguments of `PhoneConnectivityManager.buildWatchAppState`
    - the `targetDurationHours` setting

    Tests on those paths depend on the simulator's settings. Pass explicit parameters where they exist. Where they don't, add a parameter to the production code rather than writing to `.standard`.

## Making tests catch real bugs

- **Test the production code, not a copy of it.**
  - If the logic lives in a View, move it into a ViewModel or a static function first, then test that.
  - `LocationConfigTests` is the anti-example: it re-implements the view's logic inside the test, so it would pass even if `LocationConfigView` were deleted.
- **Verify saves with a fresh context.** A fetch through the same `ModelContext` also returns unsaved changes (`includePendingChanges`), so a missing `save()` would go unnoticed. Assert `!context.hasChanges`, or re-fetch through `ModelContext(container)`.
- **Assert exact results:**
  - ordered IDs, not counts
  - the specific keeper `id`, not just "one survivor"
  - the number shown, not `contains("%")`
- **Choose fixtures where the behavior changes the outcome.**
  - A test of a default parameter is worthless if every strategy gives the same answer for its fixture.
  - Dedup tests should shuffle insertion order, and the IDs must be chosen, not random.
- **Pin the time and calendar.**
  - Build dates from a fixed reference date.
  - When the production code does calendar maths (`Calendar.current`, months, days), pass in a fixed-time-zone Gregorian calendar where possible.
  - Don't compute "N days ago" as `N * 86400` seconds; it breaks across DST changes and around midnight.
- **Don't re-derive expected values with the production formula.** Write the expected value as a literal.
