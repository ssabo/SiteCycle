# CLAUDE.md

SiteCycle is an iPhone app, with an Apple Watch companion and widgets, that tracks insulin-pump infusion-site rotation and recommends the next site. Every target builds in the Swift 6 language mode.

- **Stack:** SwiftUI, SwiftData with CloudKit sync, and Swift Charts. Apple frameworks only, no third-party dependencies.
- **Minimum OS:** iOS 18.0 and watchOS 11.0.
- **No user accounts:** the iPhone is the single source of truth.

Where to look:

- **How it works:** the data model, recommendation engine, site problems and statistics are in [`docs/architecture.md`](docs/architecture.md).
- **Watch, connectivity and widgets:** see [`docs/watch-and-widgets.md`](docs/watch-and-widgets.md).
- **Known bugs and the improvement backlog:** see [`docs/reviews/2026-11-12-adversarial-review.md`](docs/reviews/2026-11-12-adversarial-review.md). Check it before working in an area, so you don't rediscover or re-introduce a listed bug.

## Layout

| Path | Target | Notes |
|---|---|---|
| `SiteCycle/` | SiteCycle (iOS app) | MVVM: `Models/` (SwiftData `@Model`s), `ViewModels/`, `Views/`, `Utilities/`, `Connectivity/` |
| `SiteCycle/Connectivity/WatchAppState.swift` | **SiteCycle, SiteCycleWatch, SiteCycleWatchWidgets, SiteCycleWidgets** | The only file compiled into several targets: the Codable phone↔watch payload and the App Group constants. It must not use anything that exists only in the iOS app. |
| `SiteCycleWatch/` | SiteCycleWatch | Thin client: no SwiftData, no CloudKit |
| `SiteCycleWatchWidgets/` | SiteCycleWatchWidgets | Watch complications |
| `SiteCycleWidgets/` | SiteCycleWidgets | iPhone widgets. Its main file has the same name as the watch widget's (`SiteCycleWidgets.swift`), so match on path, not file name. |
| `SiteCycleTests/` | SiteCycleTests | Swift Testing unit tests, hosted by the app. Read [`SiteCycleTests/CLAUDE.md`](SiteCycleTests/CLAUDE.md). |
| `SiteCycleUITests/` | SiteCycleUITests | One XCUITest smoke test. Read [`SiteCycleUITests/CLAUDE.md`](SiteCycleUITests/CLAUDE.md). |
| `scripts/check_project.py` | — | Project-file checker that runs on Linux |

**CI is Xcode Cloud** (see [`docs/xcode-cloud-setup.md`](docs/xcode-cloud-setup.md)), plus SwiftLint in `.github/workflows/lint.yml`.

Ignore these files; they describe the disabled GitHub Actions setup and are stale:

- `CI.md`
- `docs/testflight-setup.md`
- `ExportOptions.plist`
- `.github/workflows/ci.yml`, `ui-tests.yml` and `testflight.yml`

## Working without Xcode (cloud sessions)

Cloud sessions run on Linux, with no `swift`, no `xcodebuild` and no simulator, so you cannot compile or run tests there.

- **Before pushing:**
  - Run `python3 scripts/check_project.py`.
  - Run `swiftlint lint --strict` if `swiftlint` is installed.
    - The SiteCycle cloud environment's setup script installs a pinned SwiftLint, but `lint.yml` installs whatever Homebrew has, so the two can drift.
    - If local results differ from CI's, compare `swiftlint version` with the version in the "Install SwiftLint" step of the latest Lint run's log. If they differ, bump `SWIFTLINT_VERSION` in the environment's setup script to CI's version, rather than changing code to satisfy the older one.
  - Re-read your diff against the compile gotchas below, because nothing else will catch them before CI.
- **Xcode Cloud is the compile and test gate.** Its results appear as GitHub check runs on the PR:
  - `SiteCycle | CI | SiteCycleUnitTests - iOS (SiteCycle)`
  - `… | SiteCycleUITests - iOS (SiteCycle)`
  - `… | Build - watchOS`
  - `… | Archive - iOS`
- **Logs live in App Store Connect,** which you can't read. If a check fails, say which one, and ask the owner for the error output instead of guessing.
- **In the PR description,** state that the change was not compiled locally.

## Definition of done

- **Logic is tested.** Logic lives in a ViewModel or a utility, not a View, and has a unit test that fails without the change.
- **The project file is right.** New files are registered (see "Adding a Swift file"), and `scripts/check_project.py` passes.
- **SwiftLint is clean** in `--strict` mode.
- **Docs match the code.** Any doc the change makes wrong is fixed in the same commit (see "Keeping docs current").

## Keeping docs current

Docs drift when each change leaves them a little wrong, so every commit that changes behaviour updates the docs it affects.

### Scope

- **Change only what your change makes wrong.** Update docs that describe what you changed, and nothing else. Don't use a feature PR to rewrite, reorganise or "refresh" unrelated sections.
- **Unrelated drift:** if you spot drift elsewhere, mention it in the PR description, or fix it in a separate docs PR.
- **Same commit:** the doc update goes in the same commit as the code change, so the two can't drift apart in history.

### Before you commit

Check whether the change alters anything a doc states:

- a behaviour, default value or setting key
- a rule or invariant
- a file location or target membership
- a CI step
- one of the recipes below

To find mentions, search the docs for every name you added, renamed or removed:

```bash
grep -rn "<name>" CLAUDE.md */CLAUDE.md docs --include=*.md
```

Then update the doc that owns each fact:

| What changed | Doc to update |
|---|---|
| A rule, recipe or gotcha agents must follow | this file, or the nested `SiteCycleTests/CLAUDE.md` / `SiteCycleUITests/CLAUDE.md` |
| How a part of the app works, and why | `docs/architecture.md` or `docs/watch-and-widgets.md` |
| CI, signing or release setup | `docs/xcode-cloud-setup.md` |
| A known bug that you fixed | remove its **Known issue** note in `docs/`, and any "currently breaks this rule" wording in the hard rules |

`docs/reviews/2026-11-12-adversarial-review.md` is a dated snapshot. Don't rewrite its findings. Its §1 "Top 10 actions" table tracks progress:

- **When your PR completes one of those actions,** change that row's Done box from ☐ to ☑ in the same PR. You may also mark the matching §10 step done.
- **If it completes only part of an action,** leave the box ☐ and say in the PR description what remains.

### When a new doc or section is worth adding

**Add one for:**

- a new system or architectural component, such as a sync path, a persistence layer, a new target or extension, or a recommendation strategy;
- an invariant or rule that spans files and can't be seen from any one of them, such as the dedup keeper rule or the watch payload compatibility rule;
- a significant product or design decision, with its reason and the alternatives rejected, such as why P25 and not P10, or why the watch is a thin client;
- a non-obvious workflow, such as the CI setup or a release step.

**Don't add one for:**

- individual unit tests, functions, Views or small UI tweaks;
- a bug fix, unless it establishes a rule worth stating;
- anything the code already says plainly, such as parameter lists, view hierarchies or which file a type is in;
- change history ("PR #81 added…"), which belongs in git and PR descriptions.

**Keep it close:** a "why" that only matters to one function belongs in a comment next to that code, not in `docs/`.

**Keep it short:**

- New narrative goes in `docs/`. This file holds rules and recipes only.
- Extend an existing section before starting a new doc.
- If a section here starts explaining how a feature works, move that text to `docs/` and leave a one-line pointer.

## Commands (macOS, Xcode 26+)

```bash
xcodebuild build -scheme SiteCycle -project SiteCycle.xcodeproj -destination 'platform=iOS Simulator,name=<installed iPhone>'
xcodebuild build -scheme SiteCycleWatch -project SiteCycle.xcodeproj -destination 'generic/platform=watchOS Simulator'
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj -testPlan SiteCycleUnitTests -destination 'platform=iOS Simulator,name=<installed iPhone>'
swiftlint lint --strict
python3 scripts/check_project.py
```

- `xcrun simctl list devices available` lists the simulator names.
- Without `-testPlan`, `test` uses the scheme's default plan, `SiteCycle.xctestplan`, which also runs the UI test.

## Hard rules

Each rule says what enforces it. "Prose only" means nothing does yet, so take extra care.

1. **SwiftData models stay CloudKit-compatible.**
   - Every stored property is optional or has a default.
   - Every relationship is optional and has an inverse.
   - No `@Attribute(.unique)`.
   - Changes are additive only: never rename or remove a stored property or relationship, because the production CloudKit schema can't drop fields and older app versions keep syncing.
   - New fields and types must be deployed to the CloudKit Production schema (CloudKit Console) before release.
   - *Enforced by:* a violation makes the CloudKit container fail to load, which falls back silently to local storage (rule 2). Nothing fails visibly.
2. **Keep the CloudKit → local `ModelContainer` fallback** in `SiteCycleApp.makeModelContainer`.
   - Why it's needed: Xcode Cloud's Test and Build actions don't sign, so there are no CloudKit entitlements, and the app must still launch because it hosts the unit tests.
   - The catch: the fallback also hides real schema failures in production, as happened in #38. When you touch this code, surface the error; don't just `print` it.
   - *Prose only.*
3. **Dedup keepers must be the same on every device.**
   - Why: seeding and dedup run on each device before CloudKit has synced, so devices dedup the same duplicates independently. If they keep different copies, each deletes the other's, and both are gone.
   - Choose the keeper from synced record properties only:
     - For problems: a customized default first, then an enabled custom problem, then the lowest `id`.
     - For entries and locations: the lowest `id`.
   - Never decide by fetch order, entry counts or `sortOrder` ties.
   - Move relationships onto the keeper before deleting the duplicates.
   - Locations also merge the user's settings onto the keeper, from synced fields. Never OR `isEnabled` there: a freshly seeded copy is always enabled, so OR-ing turns back on a site the user disabled. Problems don't merge settings yet; they keep the preferred copy's, so a second customized copy's changes are lost.
   - **When:** on a CloudKit store, dedup runs only after a successful import, because it can move only the entries already on the device. `StoreMaintenanceCoordinator` is the only caller of `prepareStore` and `seedStore`; don't call them or a dedup function from anywhere else. See "Store maintenance" in `docs/architecture.md`.
   - **Screens that keep records:** a pass can delete a duplicate mid-session. A sheet or editor that keeps a record across user interaction must use `.holdsStoreMaintenance()`, and a view whose ViewModel caches records must refresh in `.onStoreMaintenancePass`. *Prose only.*
   - *Enforced by:* `DeduplicationTests` pins all three keepers across every insertion order, and the location settings merge. `SiteProblemTests` pins the problem keeper's preferences. `StoreMaintenancePolicyTests` and `StoreMaintenanceCoordinatorTests` pin when dedup may run.
4. **Never change a persisted identifier.** That covers:
   - `DefaultProblem.key`
   - `@AppStorage` and UserDefaults key strings
   - enum raw values stored in UserDefaults: `RecommendationStrategy`, `StatsTimeWindow`, `HomeStatMetric`
   - `WatchAppState` and `WatchSiteChangeCommand` coding keys

   Add new cases instead of renaming old ones. *Prose only.*
5. **Keep the watch payloads backward compatible.** The iPhone and watch can run different app versions, since watch installs lag behind.
   - Decode new fields with `decodeIfPresent` and a default in `init(from:)`, following `showAllLocations`.
   - Never make an existing field required, and never rename one.
   - *Enforced by:* `WatchAppStateTests` (missing-key decode).
6. **The watch is a thin client.** It never stores data or computes recommendations: the iPhone sends state, and the watch sends commands. Read `docs/watch-and-widgets.md` before changing either side.
7. **After any change to data or to a setting the watch or widgets display, call `connectivityManager.pushCurrentState()`.** It writes the App Group state, reloads the widgets and updates the watch.
   - *Prose only.* Each call site does this by hand, and some are missed; the location on/off toggle currently doesn't call it.
8. **Soft-delete anything with history.**
   - A location or custom problem that has entries gets `isEnabled = false`. Hard-delete it only if it has no history.
   - Default problems are never deleted (seeding would re-add them), only disabled.
9. **User-visible error text includes the technical error.**
   - Append `"\n\nError: <domain> <code>"` (from the `NSError`) to every error alert and every `.error(...)` state string, so failures can be diagnosed from a screenshot.
   - *Prose only.* Some call sites still miss it.
10. **Settings live in UserDefaults, with each key as a constant.**
    - Declare the key (and default and range, if it has them) as `static let`s on the type that owns the setting, as `EarlyChange.thresholdPercentKey` / `defaultThresholdPercent` do. Use those constants everywhere; don't add new string-literal keys.
    - Code outside Views reads settings through a `load(from defaults: UserDefaults = .standard)` function, so tests can pass a private suite.
    - `"targetDurationHours"`, `"absorptionAlertThreshold"` and `"hasCompletedOnboarding"` are still literals in several files. Migrate them when you touch them.
11. **No `#available` branches.** A feature must work at the deployment target, or the deployment target is raised. CI only runs the newest OS, so an old-OS branch would never be tested.
12. **Exactly one UI test.** Don't add UI tests for business logic. Move the logic into a ViewModel and unit-test it there (see `docs/ui-testing.md`).

## Change recipes

### Adding a Swift file

The project uses classic groups (`objectVersion = 60`), so every new file must be registered in `SiteCycle.xcodeproj/project.pbxproj` by hand, in four places.

1. **PBXFileReference section:**
   `<FID> /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };`
2. **PBXGroup:** add `<FID> /* Foo.swift */,` to `children` of the group whose `path` is the file's folder.
3. **PBXBuildFile section:**
   `<BID> /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = <FID> /* Foo.swift */; };`
4. **The target's PBXSourcesBuildPhase:** add `<BID> /* Foo.swift in Sources */,` to its `files`. The phase IDs are:

   | Target | Sources phase |
   |---|---|
   | SiteCycle | `…0301` |
   | SiteCycleTests | `…0310` |
   | SiteCycleWatch | `…0320` |
   | SiteCycleWatchWidgets | `…0330` |
   | SiteCycleUITests | `…0340` |
   | SiteCycleWidgets | `…0350` |

**Getting IDs:**

- Get them from `python3 scripts/check_project.py --next-ids`, and count upward for each additional file.
- Never pick IDs by hand or by pattern. The build-file ID is not "file ID + 0x100" everywhere, and IDs quoted in older docs are already taken.

**Checking:** re-run `python3 scripts/check_project.py`. It fails until all four entries are right.

**A file compiled into more than one target** needs one PBXBuildFile and one Sources entry per target. Also add it to `SHARED_SOURCES` in the script and to the Layout table above.

Converting the groups to synchronized folders, which the owner will do in Xcode, will make this recipe unnecessary. **Do not hand-write that conversion.**

### Adding a setting

1. **Constants:** add the key and default as constants (rule 10).
2. **UI:** add the control in `SettingsView`. If the watch or widgets depend on the setting, call `pushCurrentState()` from `.onChange`, and refresh any ViewModel that caches the value.
3. **Reads:** code outside Views reads it through `load(from:)`. Test with `UserDefaults(suiteName:)`, never `.standard`.
4. **Watch:** if the watch needs it:
   - add a `WatchAppState` field (rule 5);
   - fill it in `PhoneConnectivityManager.buildWatchAppState`;
   - add a test that decodes a payload without the key.

### Changing a `@Model`

- **Additive only** (rule 1). Give new properties default values in the declaration.
- **New model type:** add it to the `Schema` in `SiteCycleApp` and to every test container.
- **Other code paths:** check whether seeding, dedup, and CSV import and export need the new field.
- **Non-additive changes:** there is no `VersionedSchema` yet, so stop and ask the owner.

### Adding a default problem or location

- **Problems:** append to `DefaultProblems.all` with a new key that has never been used. Seeding inserts any missing keys, including on existing installs.
- **Locations:** default locations are only seeded into a store with no default locations, so a new default never reaches existing users. Ask the owner before relying on one.
  - Only ever append to the zones in `DefaultLocations`. Dedup reads a default's index as its seeded `sortOrder`, so reordering, inserting or removing a zone corrupts the merge.

## Compile gotchas (invisible until CI)

- **Accent colour:** `.foregroundStyle(.accent)` doesn't compile. Use `.tint`.
- **`@Observable` needs `import Observation`.** SwiftData doesn't re-export it; only SwiftUI does.
- **Modifiers that take two or more closures** (for example `.sheet(isPresented:onDismiss:content:)`) need a label on every closure; don't use trailing-closure syntax. This is also a lint rule.
- **Swift Testing:** a test that uses `try #require(...)` must be marked `throws`.
- **Main-actor isolation:**
  - ViewModels, and utility functions that take a `ModelContext`, are `@MainActor`, so test suites that use them must be `@MainActor` too.
  - `WCSessionDelegate` methods are `nonisolated`. They hop to the main actor with `Task { @MainActor in … }`, capturing only Sendable values.
  - A closure created inside a `@MainActor` method and passed to a callback-based Apple API inherits main-actor isolation, and crashes if the API calls it on a background queue (`_dispatch_assert_queue_fail`). Create such closures in a `nonisolated` context.
- **Narrow targets:** the watch, watch-widget and iPhone-widget targets compile only their own folder plus `WatchAppState.swift`. `Location`, `SiteChangeEntry`, the ViewModels and `DurationFormat` don't exist there.

## SwiftLint

CI runs SwiftLint with `--strict`, so every warning fails the build. The config is `.swiftlint.yml`. It covers every source folder except `SiteCycleUITests/`, which isn't linted yet.

The rules agents hit most:

- **`force_unwrapping`:** no `!`. In tests, use `try #require(...)`. Implicitly unwrapped optionals are banned too (`implicitly_unwrapped_optional`).
- **`empty_count`:** use `.isEmpty`, not `.count == 0`.
- **`large_tuple`:** at most 2 members; use a struct instead.
- **`identifier_name`:** names need at least 2 characters (`id` and `i` are exempt).
- **Length limits:**
  - `line_length` 150
  - `function_body_length` 50
  - `type_body_length` 300
  - `file_length` 500

  `HomeView`, `SettingsView`, `StatisticsViewModel.swift` and `SiteChangeViewModel.swift` are close to these limits. Split them into extensions, subviews or new files rather than compressing code.
