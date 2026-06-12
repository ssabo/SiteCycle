# SiteCycle Code Quality Audit — June 2026

A read-only audit of the full codebase (~9,500 lines of Swift across the iOS app, watch app,
widget extension, and test suites), conducted by five parallel specialized reviews:

1. Swift code smells & correctness (non-view code)
2. SwiftUI view layer
3. Test suite quality
4. Project hygiene (CI, lint, Xcode project, docs, repo)
5. Published best-practice comparison (2024–2026 Apple/community guidance, web-sourced)

**No code was changed.** Each finding lists severity, location, and a recommended fix.
Findings reported by multiple reviewers independently are merged and noted.

---

## Executive summary

The codebase is in better shape than typical: views are small and well-decomposed, the watch
thin-client architecture is sound, CloudKit model rules are correctly followed, the CloudKit
error classifier is unusually thorough, the CSV parser handles quoting/CRLF properly, and CI
has thoughtful touches (concurrency groups, fork guards, UI-test failure surfacing).

The problems are mostly **systemic patterns** rather than scattered local bugs:

| # | Theme | Why it matters |
|---|-------|----------------|
| 1 | **Silent error swallowing** — `try? modelContext.save()` everywhere | A failed save of a site change is invisible data loss in a health-tracking app; contradicts the project's own diagnosability rule. Found independently by 3 reviewers. |
| 2 | **CSV import deletes all data before validating** | A malformed CSV with a valid header irreversibly wipes the database and imports nothing. The single most dangerous bug found. |
| 3 | **Hand-rolled refresh model** — optional `@State` VMs + per-screen ad-hoc `refresh()` | Already produced 3 real staleness bugs (Statistics tab, zone toggle never syncing to watch, ignored settings change) and means CloudKit-imported changes from another device never appear without navigation. |
| 4 | **No privacy manifest** (`PrivacyInfo.xcprivacy`) | Hard App Store submission blocker since May 2024 — all three targets use UserDefaults (a required-reason API). |
| 5 | **No SwiftData schema versioning** | A schema evolution already happened (zone → bodyPart migration) and was handled ad hoc; retrofitting `VersionedSchema` after release is risky. |
| 6 | **iOS/watch/widget triplication** | Display names, progress thresholds, "days ago" text, badges — copy-pasted across targets with observable drift (the watch fixed a ring-clipping bug iOS still has). |
| 7 | **Documentation drift** | CI.md describes a TestFlight tag trigger and a 6-secret list that don't exist; README/CLAUDE.md claim push-to-main CI that isn't configured. |
| 8 | **Test blind spots** | Watch VMs/widgets structurally untestable (no watch test target, latent crash path), the legacy-data migration has zero tests, and several tests are tautological. |

---

## Priority 1 — Critical (data loss, crashes, submission blockers)

### C1. CSV import destroys all user data before validating rows
`SiteCycle/Utilities/CSVImporter.swift:144-145, 188-219`
`parseAndImport` calls `deleteAllData(context:)` — which **saves the deletion** — before parsing a
single data row. If every row is then skipped (bad dates, too few columns), `ImportError.noValidEntries`
is thrown but the user's entire history and all locations are already gone.
**Fix:** parse and validate all rows into in-memory structs first; only delete + insert + save once
at least one valid entry exists (or defer the delete's save and `rollback()` on error).

### C2. Silent save failures throughout the persistence layer
`SiteChangeViewModel.swift:122` (logging a site change), `HistoryViewModel.swift:50, 72, 77`,
`DefaultLocations.swift:68, 121, 160, 184`, `SiteChangeEntry.swift:40`, `SettingsView.swift:117-121`
Every `modelContext.save()` is `try?`. A failed save shows as success in the UI (in-memory object
mutated), pushes the unsaved state to the watch, and persists nothing. Contradicts the project's own
rule that errors must surface domain/code. *(Found by 3 of 5 reviewers.)*
**Fix:** make mutating VM methods `throws` or set an error state views can present; at minimum
`Logger.error` the underlying `NSError` domain/code in every catch.

### C3. No privacy manifest — App Store submission blocker
No `PrivacyInfo.xcprivacy` exists in any target, yet all three executables use UserDefaults
(`@AppStorage`, `UserDefaults.standard`, app-group suites) — a "required reason API" that App Store
Connect rejects undeclared since May 2024 (Apple TN3183).
**Fix:** add `PrivacyInfo.xcprivacy` to the iOS app, watch app, and widget extension declaring
`NSPrivacyAccessedAPICategoryUserDefaults` (reason CA92.1), health & fitness collected-data types
(not linked, not tracking), and `NSPrivacyTracking = false`.

### C4. Latent watch crash on duplicate location IDs
`SiteCycleWatch/ViewModels/WatchSiteChangeViewModel.swift:17`
`Dictionary(uniqueKeysWithValues:)` **traps at runtime** on duplicate location IDs — exactly the
condition `deduplicateLocations` exists to fix, and dedupe only runs at iOS app launch. A CloudKit
merge duplicate pushed mid-session crashes the watch app. No watch test target exists to catch it.
**Fix:** use `Dictionary(_:uniquingKeysWith:)`; see also P2-1 (dedupe on import events) and the
test-infrastructure findings (T-I4).

### C5. No SwiftData schema versioning (`VersionedSchema` / `SchemaMigrationPlan`)
`SiteCycleApp.swift:35-38`, `DefaultLocations.swift:167-186`
The schema is a plain `Schema([...])` with no version identity; the zone → bodyPart/subArea
evolution is handled by an ad-hoc, **untested** `migrateLocationBodyParts()` run on every launch.
Retrofitting versioning after release can crash staged migrations; CloudKit's add-only schema rules
make formal versioning the only safe forward path.
**Fix:** define `SiteCycleSchemaV1: VersionedSchema` + a `SchemaMigrationPlan` now; fold the
bodyPart migration into a custom stage; add unit tests for the migration (currently zero).

---

## Priority 2 — High (user-visible bugs, stale data, sync gaps)

### P2-1. CloudKit-imported changes never reach the UI; dedupe only runs at launch
- No view or VM observes import events: Home, History, Statistics, and recommendations are one-shot
  fetches refreshed only by sheet dismissals. A site change logged on another device doesn't appear
  until navigation forces a refresh. (`HomeViewModel.swift:24-26`, `SiteChangeViewModel.swift:29-37`)
- `deduplicateLocations`/`deduplicateSiteChangeEntries` run once from `onAppear`
  (`SiteCycleApp.swift:92-93`); a second device's first sync shows 28 locations (and feeds duplicates
  to the watch — see C4) until next launch.

**Fix:** `CloudKitSyncViewModel.applyEvent` (`CloudKitSyncViewModel.swift:314-317`) already knows when
an import succeeds — trigger VM re-fetches and the dedupe pass there. Longer term, consider
`@Query`-driven views for entry data (current Apple-ecosystem guidance trends this way precisely
because it eliminates the manual-refresh web).

### P2-2. Zone enable/disable toggle never saves or pushes to the watch
`SiteCycle/Views/LocationConfigView.swift:156-163`
`ZoneRow`'s toggle mutates models directly with no `modelContext.save()` and no
`pushCurrentState()` — sibling operations (add/delete/move) do both. The watch keeps recommending
disabled locations. **Fix:** hoist the mutation into a method that saves and pushes.

### P2-3. StatisticsView shows stale data after first visit; ignores settings changes
`SiteCycle/Views/StatisticsView.swift:23-32`, `StatisticsViewModel.swift:27`
- `refresh()` only runs when the VM is first created; returning to the tab after logging/editing
  shows old charts (the empty state can even persist after the first entry).
- `absorptionAlertThreshold` is read once into a `let` at VM creation with no `.onChange` — changing
  it in Settings has no effect until relaunch. For a medical-adjacent alert this silently ignores
  the user's configured threshold. (Contrast `HomeView.swift:31-33`, which handles its setting.)

**Fix:** unconditional `refresh()` on appear + `.onChange(of: absorptionAlertThreshold)`.

### P2-4. Watch→phone command path can log duplicate site changes
`WatchConnectivityManager.swift:33-41`, `PhoneConnectivityManager.swift:76-90`
`sendMessage` with a `transferUserInfo` fallback in the error handler can double-deliver;
`processCommand` has no idempotency, so two entries land seconds apart (the first closed with a
near-zero duration, polluting history and anomaly stats). `WatchSiteChangeCommand.requestedAt` is
dead code — never read on the phone. **Fix:** dedupe in `processCommand` by `requestedAt`.

### P2-5. CSV round-trip silently corrupts data in several ways
`CSVImporter.swift:177-179, 207-268`, `CSVExporter.swift:47`
- Non-numeric duration → `endTime` silently nil → row imports as an extra **active** entry
  (multiple such rows = multiple concurrent actives). Untested.
- Import wipes and recreates only locations referenced in entries: unused/disabled/custom locations
  vanish, `isEnabled` resets to true, `sortOrder` becomes first-appearance order.
- The "last word is bodyPart" heuristic mangles multi-word custom names ("Lower Back" →
  "Back (Lower)").
- Durations exported at `%.1f` hours shift reconstructed `endTime` by up to ±3 min per round trip.

**Fix:** skip-with-reason for unparseable durations; preserve unreferenced locations or export a
locations section; warn that import is destructive (and see C1).

### P2-6. CloudKitSyncViewModel lifecycle leaks
`ContentView.swift:7-10`, `CloudKitSyncViewModel.swift:230-277` *(found by 3 reviewers)*
The VM is constructed in `ContentView.init` via `State(initialValue:)` — every ContentView re-init
(e.g., when onboarding completes) creates and discards an instance whose `init` already started an
`NWPathMonitor`, a never-terminating notification Task, and an account observer. `stopMonitoring()`
is dead code (never called, no `deinit`); `accountTask` is reassigned without cancellation.
**Fix:** start monitoring lazily via `.task {}` in body; wire teardown into `deinit` or delete the
unused teardown path deliberately.

### P2-7. Core guidance invisible to VoiceOver and color-blind users
`HomeView.swift:155-176, 254-258`, `SiteSelectionSheet.swift:115-129`, `WatchLocationRow.swift:45-59`,
`StatisticsView.swift:60, 192`, widget views
- Overdue state is conveyed by ring color only; the ring has no `accessibilityLabel`/`Value`.
- Recommended/avoid badges are color-coded icons with no accessibility labels — VoiceOver users
  never hear the app's core recommendation.
- Both Swift Charts have no accessibility labels or chart descriptors.
- Fixed-size fonts and frames break Dynamic Type in several places (`WatchLocationRow.swift:27`,
  L/R badge frames, decorative icon sizes).

**Fix:** explicit "Overdue"/"Due soon" text or symbol at ≥0.8 fraction; `accessibilityValue` like
"61 of 72 hours"; labels on badges; `@ScaledMetric` for fixed frames.

### P2-8. App Review / compliance posture for a health app
- No medical disclaimer anywhere in onboarding or settings (README has one; the app doesn't).
- No privacy policy or data-handling statement in the repo (App Store requires a privacy policy URL;
  TestFlight distribution is already automated).
- Guideline 5.1.3(ii) ("may not store personal health information in iCloud") is a genuine review
  risk to assess — private-DB CloudKit sync is common in shipping diabetes apps, but the position
  should be documented before submission.
- No documented CloudKit production-schema deployment step (dev schema must be promoted in CloudKit
  Console before release or production users won't sync).

---

## Priority 3 — Medium (architecture, duplication, performance)

### Code structure & duplication
| Finding | Location |
|---|---|
| Display-name logic duplicated across targets with "must match" comments; `sideOrder` duplicated; `writeStateToAppGroup` duplicated | `Location.swift:23-36` vs `WatchAppState.swift:41-55`; `SiteChangeViewModel.swift:77-83` vs `WatchSiteChangeViewModel.swift:30-36` |
| `daysAgoText` implemented 3 times with drift (also reinvents `RelativeDateTimeFormatter`) | `HomeView.swift:143-151`, `SiteSelectionSheet.swift:131-138`, `WatchLocationRow.swift:37-43` |
| `progressColor` 0.8/1.0 thresholds in 3 targets; progress-ring ZStack duplicated — watch fixed a stroke-clipping bug (`.padding(4)`) that iOS still has (16pt stroke overhangs the 200×200 frame) | `HomeView.swift:155-176, 254-258`, `WatchHomeView.swift:52-82, 123-127`, `SiteCycleWidgets.swift:128-132` |
| Recommendation/confirmation flow copy-pasted between HomeView and SiteSelectionSheet — two `SiteChangeViewModel` instances stitched together with duplicated refresh closures | `HomeView.swift:38-60` vs `SiteSelectionSheet.swift:33-47` |
| Optional-`@State`-VM + `onAppear` scaffold replicated in 6 views, each making different refresh choices (root cause of P2-3) | HomeView, HistoryView, StatisticsView, SiteSelectionSheet, WatchHomeView, WatchSiteSelectionView |
| `LocationConfigView` embeds all zone-management business logic in the view (untestable — see T-W1); `HistoryEditView.saveChanges()` embeds diff/persistence logic | `LocationConfigView.swift`, `HistoryEditView.swift:87-122` |

**Recommended direction:** `WatchAppState.swift` is already compiled into all three targets — make it
the home for shared display formatting, thresholds, and side ordering. Extract a
`LocationConfigViewModel`. Pass one `SiteChangeViewModel` into the sheet instead of duplicating.

### Performance & correctness
| Finding | Location |
|---|---|
| `HistoryViewModel.filteredEntries` fetches **all** entries and filters in memory on every body evaluation; all three filters are expressible in `#Predicate` | `HistoryViewModel.swift:14-42` |
| Recommendation sort recomputes last-used date inside the comparator — O(n log n) comparisons × all entries per location, faulting relationships each time; same computation repeated in 2 other places | `SiteChangeViewModel.swift:41-55, 96`, `PhoneConnectivityManager.swift:66` |
| HomeView creates a new `Timer.publish` per struct init and invalidates the whole body every minute; watch already uses the better `TimelineView(.periodic)` pattern | `HomeView.swift:11-30` vs `WatchHomeView.swift:33` |
| Division by zero possible in progress math (`targetDurationHours` unguarded) | `HomeViewModel.swift:35`, `WatchHomeViewModel.swift:35` |
| Stringly-typed date-range filter; `-7 * 86400` DST-naive math; filter `now` frozen at selection time | `HistoryView.swift:11, 17, 144-160` |
| Watch pending-command spinner cleared early by a previous command's 10s timer (no generation token) | `WatchConnectivityManager.swift:45-52` |
| Watch can apply an older `WatchAppState` after a newer one (independent Task hops, no `lastUpdated` guard) | `WatchConnectivityManager.swift:89-114` |
| WatchConnectivity send/encode failures silently swallowed (`try? updateApplicationContext`, nil-returning encode/decode with no logging); empty catch on account status | `PhoneConnectivityManager.swift:29`, `WatchAppState.swift:89-110`, `CloudKitSyncViewModel.swift:360-362` |
| Phone-side `writeStateToAppGroup` is dead/broken: iOS has **no app-group entitlement** (`SiteCycle.entitlements`), and the only reader runs on the watch — falls back to an unshared container with a CFPrefs error on device | `PhoneConnectivityManager.swift:111-117` |
| Widget elapsed time goes stale: 15-min fabricated entries freeze entirely after the 2-hour window; phone never uses `transferCurrentComplicationUserInfo`. `Text(date, style: .relative)` gives live updates from one entry | `SiteCycleWidgets.swift:32-44, 86-152` |

### Modern-API & platform adoption
- **Zero localization infrastructure**: no String Catalog; many strings built via
  `String(format:)`/concatenation can never localize; manual pluralization hacks
  (`SettingsView.swift:130`). If localization is ever intended, adopt `.xcstrings` while the string
  count is small. *(Found by 2 reviewers.)*
- `DocumentPickerView` + `ActivityPresenter` reimplement `.fileImporter` and `ShareLink` with a
  fragile hidden-presenter hack (presenting from `updateUIViewController`, timing-sensitive after
  alert dismissal). Replacing both deletes ~85 lines. (`DocumentPickerView.swift`,
  `SettingsView.swift:21-33, 166-185`)
- Deprecated/legacy API on an iOS 18-only target: `.alert(item:)` with legacy `Alert`
  (`SettingsView.swift:40-46`); `.tabItem` vs the `Tab` builder and
  `.navigationBarLeading/Trailing` vs `.topBarLeading/Trailing` (`ContentView.swift:20-66`).
- `CKContainer.default()` instead of `CKContainer(identifier:)` — fragile against the
  `SITECYCLE_BUNDLE_PREFIX` indirection (`CloudKitSyncViewModel.swift:352`).
- Swift 6.2 "Approachable Concurrency" (default `@MainActor` isolation) would remove most hand
  annotations — simplification opportunity, not a bug.
- Test seams (`HistoryFixtureLoader`, `-uiTestMode` arg parsing) compiled into release builds;
  consider `#if DEBUG`.

---

## Priority 4 — Test suite

### Coverage gaps (worst first)
1. **Watch VMs + WatchConnectivityManager: zero tests, structurally untestable** — no watchOS test
   target exists; includes the C4 crash path. Either add a watch test target or move pure logic into
   the shared `WatchAppState.swift` so iOS-hosted tests cover it.
2. **Widget timeline provider: entirely untested** — timeline shape, refresh policy, fallbacks,
   `progressColor` boundaries, time formatting are pure functions locked as `private` in a target
   with no test bundle. Extract to the shared file.
3. **`migrateLocationBodyParts`: zero tests** — a regression corrupts every legacy user's data on
   launch (`DefaultLocations.swift:167-186`).
4. **CSV malformed-row edges untested** — including the silent active-entry corruption (P2-5), BOM,
   CRLF, unbalanced parens in names, negative durations.
5. **Recommendation engine gaps** — tie-breaking is nondeterministic (unstable sort with an
   inconsistent comparator) and untested; recommended *ordering* never asserted (tests check set
   membership only); disabled-location exclusion via `refresh()` untested on iOS; re-log-same-site
   untested.
6. **`PhoneConnectivityManager.processCommand` untested** (entire watch→phone log path);
   `CloudKitSyncViewModel.applyEvent` + `checkAccountStatus` untested (tests bypass via a
   test-only setter that ships in production code).
7. **UI-test gaps**: Statistics tab has zero identifiers and zero tests; CSV export/import entry
   points have no identifiers; recommendation badges, date-range filter, and both empty states have
   dead page-object members but no tests.

### Weak / brittle existing tests
- **`LocationConfigTests` is largely tautological** — five tests re-implement the production
  mutation inside the test and assert their own writes; the real logic in `LocationConfigView` has
  no unit coverage.
- `PhoneConnectivityManagerTests` reads `UserDefaults.standard` through the real app TEST_HOST — a
  persisted simulator value flips `targetDurationHours == 72` red. Inject or clean up the key.
- `CloudKitSyncViewModelTests` spin up live `NWPathMonitor`s, notification Tasks, and real
  `CKContainer.default().accountStatus()` calls that race the assertions and leak across the suite.
- `waitingTransitionsToSyncedOnSuccessfulEvent` calls the test-only setter then asserts it —
  verifies nothing.
- DST-fragile date math (`-10 * 86400` vs production calendar-day counting) fails twice a year in
  some zones (`StatisticsViewModelDurationTests.swift:137-158`).
- `LogSiteChangeFlowTests.swift:45` asserts "exactly one Active badge" with a `firstMatch` query
  that passes when **two** are active — the exact regression it guards.
- `HomeScreen.waitForAppearance` busy-waits with `Thread.sleep(0.25)`, violating the project's own
  convention.

### Infrastructure
- `makeContainer()` copy-pasted into **14** test files — extract a shared TestSupport helper.
- Naming drift: `CSVImporterTests` uses XCTest-style `test` prefixes; everything else doesn't.
- `SettingsFlowTests` re-hardcodes launch arguments that the base class already defines.

---

## Priority 5 — Project hygiene & CI

### CI/CD
| Severity | Finding |
|---|---|
| High | **No `push` trigger on `main`** — nothing verifies main after merge; README/CI.md/CLAUDE.md all claim it exists |
| High | **Signed archive + IPA export job runs on every PR** (~15+ min on 10×-billed macOS), duplicating ~80 lines of testflight.yml; not path-filtered for test-only/workflow-only changes |
| Medium | No `timeout-minutes` on any job (default 360 min on 10× runners) |
| Medium | SwiftLint unpinned (`brew install swiftlint`) — new releases break `--strict` CI unrelated to the PR |
| Medium | Actions pinned by mutable tags, not SHAs, in a repo handling Apple signing secrets; no Dependabot for actions |
| Medium | `UITestResults.xcresult` artifact has no `retention-days` (defaults to 90) |
| Low | `ci.yml:223` cleanup removes `profile.mobileprovision` but actual files are `profile_*.mobileprovision`; Xcode-select logic duplicated in 5 places with subtle drift; no DerivedData caching |

### SwiftLint
- **`SiteCycleUITests/` is not in `included:`** — ~15 files escape all lint rules.
- Valuable opt-in rules missing: `fatal_error_message`, `contains_over_filter_is_empty`,
  `empty_string`, `private_swiftui_state`, `toggle_bool`, etc.

### Xcode project
- No `SWIFT_TREAT_WARNINGS_AS_ERRORS` anywhere — SwiftLint strict covers style, not compiler
  warnings (deprecations, concurrency).
- `SWIFT_VERSION`/deployment targets/versioning duplicated across 10 target configs instead of
  project-level or the existing xcconfig; a deployment-target bump requires 6 coordinated edits.
- `DEVELOPMENT_TEAM` hardcoded in 6 configs despite the fork-friendly bundle-prefix mechanism.
- No code coverage enabled in the scheme or CI.
- *(Clean: zero dead file references in either direction; consistent Swift/OS versions.)*

### Repo & docs
- `.gitignore` missing `*.xcresult` (ui-tests writes one at repo root!), `*.xcarchive`, `*.ipa`,
  `*.p12`, `*.p8`, `*.mobileprovision` — cheap insurance given docs walk users through generating
  signing files locally.
- **CI.md badly drifted**: documents a `v*` tag trigger for TestFlight that doesn't exist (a user
  following it would push a tag and nothing happens); lists 6 secrets where workflows use 8; says
  "Xcode 16" and "altool" where reality is Xcode 26 and `-exportArchive`.
- README drift: Roadmap still lists the (shipped) Apple Watch app as future; "iOS 26.0+"
  requirement vs the actual 18.0 deployment target; Project Structure omits Connectivity/, watch
  targets, and UI tests.
- `docs/ui-testing-roadmap.md` one step stale (Step 4 merged in PR #69; Step 5 is next).
- Personal scratch scripts at repo root (`generate_icon.py`, `json_to_csv.py`) — move to
  `scripts/` or delete.
- Missing: Dependabot config, issue/PR templates, CHANGELOG, `PRIVACY.md` (see P2-8).

---

## Suggested sequencing (if/when you act)

**Bucket A — do first (small, high-impact, independent):**
1. C4 one-line watch crash fix (`uniquingKeysWith:`)
2. C1 CSV import: validate-before-delete
3. C3 privacy manifests (3 small plist files)
4. Quick hygiene wins: push-to-main trigger, `timeout-minutes`, `.gitignore` entries,
   `retention-days`, Dependabot, SwiftLint `included:` UI tests — all one-to-few-line changes
5. Fix CI.md's phantom tag trigger + secrets table

**Bucket B — systemic fixes (each is a focused PR):**
6. C2 error-surfacing pass over all `try? save()` sites
7. P2-1/P2-4: react to CloudKit import events (refresh + dedupe) and dedupe watch commands
8. P2-2/P2-3: zone-toggle save/push + Statistics refresh/onChange
9. C5 `VersionedSchema` + migration tests

**Bucket C — structural investment:**
10. Shared presentation helpers in `WatchAppState.swift` (names, thresholds, days-ago, ring)
11. Consistent refresh convention or `@Query` adoption; extract `LocationConfigViewModel`
12. Accessibility pass (P2-7); String Catalog if localization is wanted
13. Test-suite hardening (shared `makeContainer`, de-tautologize LocationConfigTests, watch/widget
    logic relocation, CSV edge tests)
