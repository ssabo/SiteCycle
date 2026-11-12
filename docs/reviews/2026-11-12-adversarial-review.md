# SiteCycle adversarial review (2026-11-12)

This is a whole-repo review, done by nine parallel reviewers plus a verification pass:

- agent docs
- tests
- persistence/sync
- business logic
- SwiftUI views
- watch/connectivity/widgets
- build/CI
- cross-cutting architecture
- iOS 27 research

The review is **static only**. The cloud environment has no Swift toolchain or `xcodebuild`, so nothing was compiled or run.

**Evidence tags**

- **✅ Verified:** I re-read the code after a reviewer reported it.
- **🔎 Reviewer-verified:** a reviewer traced the code path, and I did not re-check it.
- **❓ Plausible:** the code is as described, but the outcome depends on runtime or OS behaviour that needs a device to confirm (see §9).

Line numbers are as of `b3054fb`.

---

## 1. Executive summary

The codebase is tidy for its size:

- Swift 6 language mode is on in every target.
- The SwiftData models are CloudKit-compatible.
- The pbxproj has no duplicate or dangling IDs.
- The recommendation-strategy tests are strong.

The serious problems are concentrated in three places.

1. **Destructive or non-deterministic data paths.** These are the CSV import, location dedup and dedup timing. They can erase or orphan a user's history, and CloudKit then syncs the damage to every device. For a medical-adjacent app this is the top priority.
2. **Cross-device and watch edge cases.** Watch commands are logged at the wrong time. Nothing refreshes after a CloudKit import. "Only one active site" is not enforced.
3. **Agent manageability.** Agents cannot build, test or see test logs anywhere they work. CLAUDE.md is about 60% feature narration that is going stale, and its pbxproj recipe would corrupt the project if followed literally. Important invariants live only in prose, and at least one, the dedup keeper rule, is already violated.

**Top 10 actions, in order**

| # | Action | Why |
|---|---|---|
| 1 | Make CSV import validate rows before deleting anything, and confirm before restoring during onboarding | ✅ An all-invalid file, such as one re-saved in Excel, wipes all history on all devices |
| 2 | Make the location dedup keeper deterministic, stop OR-ing `isEnabled`, and run migration before dedup | ✅ Two devices can each delete the other's copy, orphaning history; dedup re-enables sites the user disabled |
| 3 | Fix the crash paths: confirmation-sheet `ClosedRange`, `DurationFormat` on non-finite values, onboarding missing environment | ✅ Release-build traps reachable from user data |
| 4 | Honour `WatchSiteChangeCommand.requestedAt`, add a command ID, and activate WCSession at launch | ✅ Queued watch changes are logged hours late or out of order, which corrupts durations and stats |
| 5 | Enforce a single active entry (close all open entries; add a repair pass) | ✅ Multiple "Active" entries are reachable from History, CSV and two devices |
| 6 | Make `stale-branch-cleanup.yml` never delete a branch with an open PR, and default `dry_run` to true | ✅ It can delete live agent branches and close their PRs |
| 7 | Add `PrivacyInfo.xcprivacy` to all 4 bundles (UserDefaults reasons) | ✅ Missing; App Store Connect requires it |
| 8 | Device-check whether PR #70's App Group entitlement moved the SwiftData store | ❓ It may have orphaned the pre-August store |
| 9 | Convert to synchronized folders, then extract a Foundation-only `SiteCycleCore` package tested on Linux | Removes hand-editing of the pbxproj, and gives agents a test loop |
| 10 | Rewrite CLAUDE.md to about 110 lines of rules and change recipes; move the feature narration out | The current file is stale in at least 15 places |

---

## 2. Fix now: data loss and crashes

### 2.1 CSV import erases all history when no row is valid ✅ (critical)

- **The code.** `CSVImporter.parseAndImport` calls `deleteAllData` (`CSVImporter.swift:146`). That deletes every entry and location and **saves** (`:266-277`). Only afterwards does `importEntries` parse the rows, and it throws `.noValidEntries` when none parse (`:197`).
- **What the user sees.** The alert says "Import Failed", which implies nothing happened. The deletes have already been exported to CloudKit.
- **Realistic trigger.** The user opens a backup in Excel or Numbers and saves it. Dates are rewritten as `11/12/2026 8:00`, every row fails the ISO 8601 parse, and all history is gone on every device.
- **Onboarding makes it worse ✅.** "Restore from CSV backup" (`OnboardingView.swift:78-84, 107-113`) runs the same import with **no confirmation**. `hasCompletedOnboarding` is stored per device, so this screen appears on every new phone or reinstall, often while CloudKit is still downloading the user's real history. It also never calls `pushCurrentState()`.
- **Other lossy behaviour 🔎:**
  - An unparseable duration ("72h") silently becomes an **active** entry (`:184-186`).
  - A stray `"` in the middle of a field swallows the rest of the file into one note.
  - The export rounds durations to `%.1f`, which shifts end times by up to 3 minutes and defeats exact-match entry dedup.
  - All locations are deleted and only the ones named in the CSV are recreated. Disabled flags, sort order and unused custom zones are lost, and `seedDefaultLocations` never restores the defaults because the count is non-zero.
  - Custom names such as "Lower Back" round-trip as "Back (Lower)".
- **Fix:**
  - Parse everything into value structs first.
  - Abort with the store untouched if nothing is valid; ideally show "N rows invalid, continue?".
  - Delete and insert in one save, and call `rollback()` on error.
  - Write an automatic pre-import backup.
  - In onboarding, show the Settings "Replace All Data?" confirmation, and refuse when entries already exist.
  - Export an exact end timestamp.
  - Tests: `importAllInvalidRowsPreservesExistingData`, plus an export→import round-trip test.

### 2.2 Location dedup breaks the project's own determinism rule ✅ (high)

- **The rule.** CLAUDE.md says dedup keepers must come "from synced record properties only, never fetch order or entry counts".
- **The code.** `deduplicateLocations` (`DefaultLocations.swift:99-104`) sorts by `safeEntries.count`, then `sortOrder`. Seeded duplicates tie on `sortOrder`, so the final tie-break is fetch order. PR #81 fixed exactly this for problems but missed locations. CLAUDE.md does not describe the location keeper at all.
- **Scenario A, both devices delete each other's copy.** Two fresh devices seed 14 identical defaults. Each prefers its own rows, deletes the other device's, and syncs; both copies end up deleted. The nullify rule then sets `entry.location = nil` for that history.
- **Scenario B, reinstall.** On a reinstall, entry-to-location links arrive after the location records. The old locations look unused, the new copies win, and the old ones are deleted. History is orphaned and recommendations treat every site as never used.
- **Re-enable bug ✅.** `if duplicate.isEnabled { keeper.isEnabled = true }` (`:112-114`). Freshly seeded duplicates are always enabled, so every new device turns back on a site the user disabled (for example, because of lipohypertrophy) and syncs that everywhere.
- **Ordering bug 🔎.** `SiteCycleApp.swift:85-87` runs `deduplicateLocations` **before** `migrateLocationBodyParts`. Legacy rows all have `bodyPart == ""`, so all left sites collapse into one location and all right sites into another. This only affects stores from before the `bodyPart` migration, but it can't be undone.
- **Fix:**
  - Add an additive `defaultKey: String?` to `Location`, mirroring `SiteProblem`.
  - Make the keeper the lowest `id`.
  - Copy customisations from whichever copy differs from its seeded state; never OR `isEnabled`.
  - Swap the migrate/dedup order.
  - Add an order-independence test for all three dedup functions: shuffle the insertion order and assert the same survivor `id`.

### 2.3 Dedup runs only at launch, possibly mid-import ❓ (high)

- **Why the keeper rule isn't enough.** A deterministic keeper prevents both copies from being deleted. It does not protect links that haven't arrived yet.
- **Scenario.** `deduplicateProblems` re-points only `duplicate.safeEntries` that are present locally (`DefaultProblems.swift:76-85`). A new device that dedups before entry links arrive deletes copy P_A. On device A, nullify then strips P_A from its entries, and A never re-points them.
- **`isCustomizedDefault` uses mutable fields.** A rename on the other device mid-sync can flip which copy is the keeper.
- **Fix:**
  - On a device with iCloud available, seed only after the first successful CloudKit `.import` event, with an offline timeout fallback.
  - Re-run dedup, debounced, after each successful import.
  - Consider tombstones (`mergedInto: UUID?`) instead of hard deletes, so late links can be re-pointed.

### 2.4 PR #70 may have relocated the SwiftData store ❓ (verify on device first)

- **What changed.** Commit `e21234d` added `com.apple.security.application-groups` to `SiteCycle.entitlements`. The `ModelConfiguration` sets neither `url:` nor `groupContainer:`.
- **The concern.** With `groupContainer: .automatic`, SwiftData may place the default store in the app-group container once that entitlement exists. Users who upgraded across #70 would then have started on an empty store:
  - Synced users re-imported their data, and hit the races in §2.2 and §2.3 while doing so.
  - Users without sync saw their history vanish.
- **Action:**
  1. Log `container.configurations.first?.url` on a pre-#70 build and on the current build.
  2. If the location moved, pin the URL to the *current* location (don't move it back).
  3. Add a one-time rescue that imports entries missing from the current store out of the legacy file, matched by `id`.

### 2.5 Crashes reachable from user data ✅

- **Confirmation sheet `ClosedRange` trap.**
  - **The code.** `SiteChangeConfirmationSheet.swift:188` builds `in: earliestChangeTime...Date()`, where `earliestChangeTime` is `previousEntry.startTime`. A future start time makes the lower bound exceed the upper, and `ClosedRange` traps, including in Release builds.
  - **How to get there.** `HistoryEditView`'s Start Time picker has no upper bound, and CSV import and clock-skewed CloudKit records add more ways in. Once the active entry has a future start, every site change crashes until the user finds and fixes that entry.
  - **Fix.** Use `min(earliest, now)...now`. Validate in `HistoryViewModel` that start ≤ now and end ≥ start. Clamp in `logSiteChange`.
- **`DurationFormat.hoursMinutes` traps and truncates.**
  - **The crash.** `Int(hours)` traps on NaN, ±infinity or values larger than `Int` can hold. CSV import accepts `"nan"`, `"inf"` and `"1e300"` (`Double(_:)`), so History crashes on every device after sync.
  - **The minute error.** Truncating also drops a minute in about 46% of exact-minute durations: 31h 24m (CLAUDE.md's own example) renders as "31h 23m".
  - **Negative values** come out wrong: −1.5h shows "-30m".
  - **Fix.** `guard hours.isFinite`, round the total to whole minutes, then handle the sign. Use `@Test(arguments:)` with 3660 s, 7380 s and 72.4 h.
- **Onboarding is missing `PhoneConnectivityManager` ✅.**
  - **The code.** `SiteCycleApp.swift:93-99` applies `.environment(connectivityManager)` to `ContentView` *inside* `.fullScreenCover`, so `OnboardingView` doesn't inherit it. `OnboardingView` embeds `LocationConfigView`, which declares a non-optional `@Environment(PhoneConnectivityManager.self)` and uses it in its add, delete and move handlers (`:100, :119, :134`).
  - **Effect.** Adding, deleting or reordering a zone during onboarding is a fatal "No Observable object" error.
  - **The known crash.** This is the strongest candidate for CLAUDE.md's "Welcome → Configure" crash: the property arrived in #54 and the crash was first seen in #67. It explains that crash only if SwiftUI resolves the property eagerly; confirm on device.
  - **Fix.** Inject the manager into the cover's content as well, and into all `#Preview`s, which have the same gap.
- **Watch `sendMessage` error handler ❓.** `WatchConnectivityManager.swift:36-38` passes a closure formed in a `@MainActor` method. Under Swift 6 that closure is main-actor isolated, but WCSession calls it on a background queue, and the isolation check fails with `_dispatch_assert_queue_fail`. That is the same signature that commit `99a5569` (#58) attributed to a "WCSession XPC bug" and fixed by dropping the reply handler. If this is right, the fallback `transferUserInfo` never runs and the site change is lost.
  - **Fix.** Send from a `nonisolated static` helper with an explicitly `@Sendable` closure.
  - **Test on device.** Force-quit the iPhone app, then log a change from the watch.

### 2.6 Watch commands use the wrong time and aren't idempotent ✅ (high)

- **The code.** `WatchSiteChangeCommand.requestedAt` (`WatchAppState.swift:128`) is never read on the phone. `PhoneConnectivityManager.processCommand` (`:95-108`) calls `logSiteChange(location:note:nil)`, so the change time is `Date()` at receipt.
- **Late delivery.** The watch falls back to `transferUserInfo`, which waits until the phone app runs.
- **The phone may not be listening ❓.** WCSession is activated only in `ContentView.onAppear` (`SiteCycleApp.swift:90`), so a background launch, with no UI scene, never activates it.
- **Scenarios:**
  - **Late:** a 07:00 tap that arrives at 12:00 gives the previous site 5 extra hours and starts the new one at 12:00. The ring and complications then run 5 hours behind.
  - **Out of order:** the user logs on the phone, and an older watch command then overrides it.
  - **Duplicates:** a retry after the 10 s pending timeout produces a 0-minute entry.
  - **Silently dropped:** a command for an unknown location is discarded with no feedback.
  - **Disabled sites accepted:** a command for a disabled location is applied, because `isEnabled` is never checked.
- **Fix.** Write a pure, unit-tested `WatchCommandApplier.apply(command, active:, now:)` that:
  - clamps `requestedAt` to the range from the active entry's start to now;
  - rejects or backfills commands older than the active entry's start;
  - ignores the same location within about 2 minutes;
  - carries an optional `commandId`, decoded as nil when missing;
  - always pushes state back to the watch.

  Separately, activate WCSession in `App.init` and add `.backgroundTask(.watchConnectivity)` on the watch.

### 2.7 "One active site" is not enforced ✅ (high)

- **The code.** `logSiteChange` closes only `fetchActive` (`fetchLimit = 1`, `SiteChangeViewModel.swift:324`).
- **Ways to get a second active entry:**
  - In History, turning off "Has End Time" on any old entry.
  - In CSV import, an unparseable duration.
  - Two devices logging a change offline.
  - The stale-snapshot reopen in `HistoryEditView` (§3).
- **Effects.** History shows several "Active" badges, Statistics skips the extras forever, and export writes them back out as active.
- **Fix:**
  - Close every open entry that started at or before `changeTime`.
  - Add a launch and post-import repair pass that closes each non-latest open entry at the next entry's start.
  - Allow clearing the end time only on the latest entry.

### 2.8 The CloudKit → local fallback is silent ✅ (high)

- **The code.** `SiteCycleApp.swift:53-76` falls back to `.none` and only calls `print`.
- **It has already hidden a bug.** Commit `d57410c` (#38) records that missing defaults made the CloudKit container fail and "fall back to local-only storage". Sync was silently off for everyone.
- **What the user sees.** A grey icon and "iCloud is not available", with no error domain or code, which breaks the project's own error-string rule.
- **Crash loop.** If the failure is a store or migration error, the `.none` attempt fails the same way and `fatalError` crashes on every launch, with no way to export.
- **Fix.** Surface the error. Allow the silent fallback only in DEBUG and unsigned CI builds (keep it, since Xcode Cloud Test actions don't sign). Replace `fatalError` with a recovery screen.

### 2.9 Repo safety and compliance ✅

- **`stale-branch-cleanup.yml` can delete live branches.** Open PRs are exempt only if they carry a `keep-branch` label (`:80-94`). Otherwise:
  - A branch with any merged PR older than 14 days is deleted, even if newer commits or a new open PR exist.
  - Any branch idle for 44 days is deleted.

  Reused `claude/*` branches are exactly this case. Manual runs default to `dry_run: false`.
  - **Fix.** Never delete a branch with any open PR. In the merged path, delete only when the branch tip equals the merged PR's `head.sha`. Default `dry_run` to true.
- **No `PrivacyInfo.xcprivacy` in any bundle.** UserDefaults and `@AppStorage` are a required-reason API and are used by the app, the watch app and both widgets. Add a manifest per bundle with `NSPrivacyAccessedAPICategoryUserDefaults`; per the reviewers, the codes are CA92.1 for app-only defaults and 1C8F.1 for App Group defaults (confirm against Apple's list). `SiteCycleWidgets` has no Resources build phase yet, so one must be added. Check App Store Connect emails for ITMS-91053.

---

## 3. Other correctness bugs

| Sev | Bug | Evidence | Fix |
|---|---|---|---|
| M ✅ | **Edits synced in from another device get overwritten.** The confirmation sheet compares its snapshot with the *live* entry, so an unedited sheet sends `.replace(oldSnapshot)` over a synced edit, the opposite of its doc comment. *(The views reviewer called this correct; it isn't.)* `HistoryEditView.saveChanges` does the same. If the watch closes the entry while the edit screen is open, Save reopens it. | `SiteChangeConfirmationSheet.swift:106-117`; `HistoryEditView.swift:109-146` | Diff against the values captured at open. Extract an `EntryDraft` with `changes(from: original)` and unit-test it |
| M ✅ | **The watch circular complication never turns red.** The fraction is capped at 1.0 *before* the colour is chosen. | `SiteCycleWatchWidgets/SiteCycleWidgets.swift:98-99` | One shared progress helper (see the duplication section) |
| M ✅ | **No refresh after CloudKit imports.** Watch, widgets and Home stay stale until the app is next foregrounded or a screen triggers a refresh; `CloudKitSyncViewModel` only updates its icon. | grep: no `NSPersistentStoreRemoteChange` or `didSave` observer | One change monitor that pushes and refreshes on import and save (§6) |
| M 🔎 | **Widgets show elapsed time in 15-minute steps.** Elapsed time is precomputed per entry, so values can be up to 15 minutes out of date and freeze if a reload is late. | Both providers `:32-43` | `Text(start, style: .relative)` or `ProgressView(timerInterval:)`; entries at 80%/100% thresholds |
| M 🔎 | **Watch complications stay stale.** The iPhone never calls `transferCurrentComplicationUserInfo`, and the watch has no background task. | `PhoneConnectivityManager`, `SiteCycleWatchApp` | Add both; per the iOS 27 reviewer, watchOS 27 fixed this call for WidgetKit complications |
| M 🔎 | **Location on/off toggle neither saves nor pushes.** The watch keeps offering a disabled site and the phone accepts it. | `LocationConfigView.swift:156-163` | Route through a ViewModel that saves and pushes; reject disabled IDs in `processCommand` |
| M 🔎 | **The anomaly filter hides the early failures P25 is meant to show.** It drops every site under 12h, plus an IQR fence that is near zero for consistent users: three painful 48h sites among nine at 72h are all filtered out, and P25 jumps from 65.7h to 71.8h. | `StatisticsViewModel.swift:218-246` (12h floor ✅) | Don't filter sites with recorded problems; use a floor relative to the target or none |
| M 🔎 | **With 3 or fewer enabled sites, recommendations are empty.** The avoid list takes all of them. On the watch with Show All off, the picker is empty and the user can't log at all. | `SiteChangeViewModel.swift:126-127`; `WatchSiteSelectionView.swift:62-93` | Cap avoid at `min(3, enabled - 1)` |
| M 🔎 | **"Site Rest Time" is measured from `startTime`.** The site currently worn shows about 3 days of "rest". | `StatisticsViewModel.swift:272-282` | Measure from `endTime`; show the active site as in use |
| M 🔎 | **Settings changes ignored until relaunch.** The absorption threshold is a `let` captured at VM creation. | `StatisticsViewModel.swift:116` | Make it a `var` with an `.onChange` |
| M 🔎 | **The History date filter freezes "now".** New entries stay hidden until the range is picked again; the filter also uses 86,400-second days, while Statistics uses calendar days. | `HistoryView.swift:176-192` | `enum HistoryDateRange`, with bounds computed at fetch time |
| M 🔎 | **Leaked monitors.** `ContentView` builds a new `CloudKitSyncViewModel` on every init (`State(initialValue:)`), and each one leaks an `NWPathMonitor`, a `for await` task and an observer. Separately, "synced" can show after a failed export. | `ContentView.swift:9`; `CloudKitSyncViewModel.swift:230-264, 308-325` | Own it in `SiteCycleApp`; track state per event type |
| L ✅ | **Choosing "None" as History location is ignored.** nil means both "unchanged" and "set to None". | `HistoryEditView.swift:112` | Use an explicit enum |
| L ✅ | **Strategies break never-used ties in opposite directions.** By Site picks the *highest* `sortOrder` (`suffix(3).reversed()`); the other two strategies pick the lowest. | `SiteChangeViewModel.swift:135` | Use one comparator, `isLessRecentlyUsed`, everywhere |
| L ✅ | **The `allSorted` comparator is not a strict weak ordering.** Sort order becomes undefined when an L/R pair's sort orders aren't adjacent, which CSV restore produces. It is copied into the watch VM. | `SiteChangeViewModel.swift:147-152` | Compare a lexicographic key `(sortOrder-of-pair, sideOrder)` |
| L ✅ | **App group derivation mangles some custom prefixes.** It uses `replacingOccurrences` anywhere in the string, so a prefix containing `.widgets` breaks it, and `UserDefaults(suiteName:)` fails silently. | `WatchAppState.swift:11-18` | Strip exact suffixes, or read the group ID from Info.plist via a build setting |
| L 🔎 | **The HomeView timer restarts on every re-render.** `Timer.publish` is recreated on every init. | `HomeView.swift:22` | `TimelineView(.everyMinute)` |
| L 🔎 | **"Days ago" counts 24-hour spans, not calendar days.** It disagrees with Statistics, and there are 3 copies. | `HomeView:172`, `SiteSelectionSheet:134`, `WatchLocationRow:36` | Shared calendar-day helper |
| L 🔎 | **Wrong plurals and string-built numbers.** "1 uses" and "1 rows were skipped"; `String(format:"%.1f")` ignores the locale. There is no String Catalog. | `StatisticsView:223`, `SettingsView:257` | Use a String Catalog and `FormatStyle` |
| L 🔎 | **Error-string rule violated.** Import alerts and `CloudKitSyncViewModel:100` lack the "Error: domain code" suffix, and `CSVImporter:38` `try?` throws away the real read error. | — | Type-level error factory (§5) |
| L 🔎 | **About 18 `try? save()` calls swallow failures.** A failed save in `logSiteChange` leaves the UI showing a change that was never persisted. | — | Error policy (§6) |

---

## 4. Tests

The suite has 301 `@Test`s across 23 files, all registered in the pbxproj. Every container schema includes all 3 models.

**Strong.** Recommendation strategy and cooldown, problem statistics, CloudKit error mapping. Custom-defaults tests correctly use UUID-named suites.

**Weak or misleading (verified ✅ / reviewer-verified 🔎).**

- ✅ **`LocationConfigTests` never calls production code.** It re-implements the view's soft/hard-delete and reorder logic inside the test, then checks that SwiftData kept what the test wrote. It would pass with `LocationConfigView` deleted. `docs/ui-testing.md` says this logic is "already covered", and it is not.
- ✅ **`CloudKitSyncViewModelTests.waitingTransitionsToSyncedOnSuccessfulEvent` is a tautology.** It calls `setStateForTesting(.synced)` and reads the value back. The real `applyEvent` is untested.
- 🔎 **No test can detect a missing `save()`.** Every test reads back through the same context, and `includePendingChanges` defaults to true. Deleting `save()` from `logSiteChange`, any History mutator, seeding or dedup passes the suite, yet CloudKit only syncs saved changes. Assert `!context.hasChanges`, or re-fetch through a fresh `ModelContext(container)`.
- 🔎 **Tests that can't fail for the bug they name:**
  - `defaultParameterMatchesBySiteStrategy`: all strategies give the same answer for its fixture.
  - `defaultCooldownParameterIsTwo`: N=1 and N=2 give the same result.
  - The problem-merge dedup test uses random IDs, so it catches a regression only about 50% of the time.
  - `isCustomizedDefault` tests change several fields at once, so a missing clause survives.
  - `WatchAppStateTests` compares counts, not IDs.
- 🔎 **The host app runs normally during unit tests.** No plan passes launch arguments, so the hosted app opens the on-disk CloudKit store, seeds and dedups it, activates WCSession and writes to the App Group. On a signed developer simulator this touches real iCloud data. `PhoneConnectivityManagerTests:28` asserts `targetDurationHours == 72` read from `UserDefaults.standard`, so it fails on a simulator where the setting was changed. Pass `-uiTestMode` (or a new `-unitTestHost`) plus pinned defaults such as `-targetDurationHours 72` in the unit plans.
- 🔎 **Time-dependent tests.** Some build "N days ago" from 86,400-second offsets while production uses `Calendar.current`, so they fail across DST and midnight. The CSV filename test re-implements the production formatter.
- ✅ **The default test plan includes UI tests.** `SiteCycle.xctestplan` is the scheme default, so CLAUDE.md's "run tests (iOS only)" also runs the smoke test.

**Mutations no test catches** (from the test reviewer's thought experiment):

- the `isEnabled` predicate in `refresh()`
- any location-dedup keeper rule
- all-invalid CSV, BOM, CRLF or bad-duration rows
- the inclusive/exclusive edge of the stats time window
- `applyEvent`
- `WatchAppState` ID fidelity
- History `isDeleted` handling

**Tests to add, in priority order.** T1, T2, T3, T6 and T13 fail against today's code.

1. **T1** `importAllInvalidRowsPreservesExistingData`
2. **T2** `durationFormatExactMinutes(arguments:)`: 3660 s → "1h 1m", 7380 s → "2h 3m", 72.4h → "72h 24m", NaN does not crash
3. **T3** `csvRoundTripPreservesData`: custom names, notes containing `,` `"` and `\n`, problems, the active entry
4. **T4** BOM and CRLF handling in `parseCSV`
5. **T5** an unparseable duration is skipped, not imported as active
6. **T6** `deduplicateLocationsKeeperIsDeterministic`: shuffled insertion order and different entry counts give the same survivor
7. **T7** the confirmation/History edit diff ignores a concurrent synced change (after extracting `EntryDraft`)
8. **T8** `logSiteChangePersists`: `!context.hasChanges`, and a fresh context sees both entries; same for each History mutator
9. **T9** `isCustomizedDefault(arguments:)`: each field triggers it on its own
10. **T10** a disabled location is excluded from recommendations, Statistics and Home
11. **T11** two active entries: decide the behaviour, then pin it
12. **T12** `applyEvent` mapping (after extracting it): start → syncing, success → synced, failure → error
13. **T13** the `allSorted` comparator is consistent with non-adjacent L/R pairs
14. **T14** `appGroupIdentifier(for:)` table over all 4 bundle IDs; the watch command applier (§2.6)
15. **T15** days-since-last-use across DST, with an injected calendar and a fixed `now`

**Delete or merge:**

- Delete `LocationConfigTests` and replace it with tests of an extracted ViewModel.
- Delete the tautological and duplicate tests: the two `uniqueIDGeneration` tests and the init-value tests.
- Collapse near-duplicates into `@Test(arguments:)` tables: the Statistics mean/median/min/max tests, the `handleTap*` tests, the CKError codes, the display names.
- Replace the hand-written CSV parser in `CSVExporterTests` with `CSVImporter.parseCSV`.

**Infrastructure:**

- Add `SiteCycleTests/TestSupport.swift` with `makeTestContext()`, which replaces 20 copies of `makeContainer()`.
- Add fixture builders, a fixed `Fixture.now`, and a fixed-time-zone Gregorian calendar.
- Seams to add:
  - a settings snapshot instead of `UserDefaults.standard`
  - `now:` and `calendar:` parameters
  - a pure watch-command handler
  - an injectable account-status provider

---

## 5. Agent docs (CLAUDE.md and friends)

**Verdict.** The owner's scepticism is justified.

- CLAUDE.md is about 25 KB. About 60% narrates feature behaviour that duplicates code comments and drifts. PRs #78, #80, #81 and #82 each appended a changelog-like section.
- The real rules (pitfalls, lint, adding files, concurrency) total about 2 KB.
- Critical guidance for the environment agents actually work in is missing.

**Wrong or stale statements in CLAUDE.md (verified):**

- **Adding files:** the example IDs `…0013` and `…0113` are already used by `LocationConfigTests.swift`. Following the recipe literally creates a duplicate ID. The "+0x100" pairing doesn't hold for 23 of 80 build files, and build file `…0246` sits in the PBXGroup range.
- **Test container snippet:** `Schema([Location.self, SiteChangeEntry.self])` omits `SiteProblem`. All 20 real copies include it.
- **Test command:** `xcodebuild test -scheme SiteCycle` "(iOS only)" also runs UI tests (§4). Use `-testPlan SiteCycleUnitTests`.
- **Location model:** the field list omits `bodyPart` and `subArea`. The `displayName` example "Left Front Abdomen" is wrong; it is "Abdomen (Front)", and `fullDisplayName` is "L Abdomen (Front)".
- **All Locations:** described as sorted by most recent use; it is sorted by `sortOrder` with left before right.
- **Recommendations:** cooldown recommendations "never go empty"; they do with 3 or fewer sites.
- **App initialisation:** omits `deduplicateLocations`, `deduplicateSiteChangeEntries` and `migrateLocationBodyParts`, and never mentions that CSV import is destructive.
- **CI section:** says the "Watch app's ModelContainer" has a fallback, but the watch has no ModelContainer (CLAUDE.md says so itself later). It says `ci.yml` "ran on every push and PR"; it was PR-only.
- **Watch:** "Watch → Phone: transferUserInfo" — it actually calls `sendMessage` first and falls back to `transferUserInfo`. The complication timeline description is backwards.
- **`pushCurrentState()`:** said to be called "after location config changes", but not for the most common one, the on/off toggle.
- **Known app bug:** the note on the onboarding crash duplicates `docs/ui-testing.md`, and §2.5 has the likely cause.

**Elsewhere:**

- **README** says "iOS 26.0+" (the target is 18.0) and "three targets" (there are four). Its project tree is half missing, it says GitHub Actions builds every push, and it lists the watch app as a future roadmap item.
- **`CI.md`** is wrong throughout: Xcode 16, an active `ci.yml`, `altool`, tag triggers, 6 secrets instead of 8.
- **`docs/custom-bundle-id.md`** and the xcconfig comment omit the `.app.widgets` bundle and call the App Group "optional", when the iPhone widget requires it.
- **The disabled workflows** (`ci.yml`, `ui-tests.yml`, `testflight.yml`) look live from inside the repo. Their "rollback" story is already broken: there is no profile for the iPhone widget.

**Invariants that live only in prose, and how to enforce them:**

| Invariant | Enforce with |
|---|---|
| Never change a default problem's `key` | Pin the literal key list in a test; today the test compares `DefaultProblems.all` with itself |
| Dedup keepers are device-independent | Shuffled-order property test for problems, entries and locations |
| `WatchAppState` stays backward compatible | Decode a frozen JSON fixture of the oldest payload |
| `LocationInfo` naming matches `Location` | One shared naming function in the shared file |
| Settings keys and defaults | A typed `AppSettings` registry, plus a SwiftLint `custom_rules` regex banning `@AppStorage("` and `forKey: "` literals |
| Error string format | Build `.error` from an `NSError` through a factory that formats the suffix; then delete the prose rule |
| Call `pushCurrentState()` after every mutation | A central change monitor (§6); then delete the rule |
| New files registered in pbxproj | `scripts/check_project.py` in lint CI and a hook; eventually synchronized folders |
| UI tests are linted | Add `SiteCycleUITests` to `.swiftlint.yml` `included:` |

**Proposed CLAUDE.md, about 110 lines:**

1. **What this is.** Two lines, plus a table of directory → target(s), flagging `WatchAppState.swift` as shared by 4 targets and the two `SiteCycleWidgets.swift` files.
2. **Working without Xcode.** Cloud agents can't compile or test. Run `scripts/verify.sh`, and state "not compiled locally; Xcode Cloud is the compile gate" in the PR. Say how to read Xcode Cloud check status on the PR.
3. **Definition of done.** Lint clean, project check passes, logic in a ViewModel or Core with unit tests, docs updated only when a *rule* changes.
4. **Commands (macOS).** Build, `-testPlan SiteCycleUnitTests`, `swiftlint lint --strict`.
5. **Hard rules.** Numbered and imperative, each pointing at the test or code that enforces it: CloudKit model rules (optional or defaulted, no `.unique`, additive only), dedup keepers, default keys, watch payload compatibility, the fallback, error format, settings keys, soft delete, thin-client watch, UI-test policy, no `#available` branches.
6. **Change recipes.** New Swift file; new setting; new `@Model` property; new watch-visible field; new default problem or location; new target.
7. **Compile gotchas you won't see on Linux.** Keep the current SwiftUI pitfalls; add Swift Testing `throws`, `@MainActor` and `import Observation`.
8. **SwiftLint rules that bite.** Add `line_length` 150, `identifier_name` minimum 2, and `implicitly_unwrapped_optional`.
9. **Further reading.** `docs/architecture.md` (recommendations, problems, statistics reasoning), `docs/watch-and-widgets.md`, `docs/xcode-cloud-setup.md`, `docs/ui-testing.md`.

**Also:**

- Add nested `SiteCycleTests/CLAUDE.md` (shared test context, UserDefaults suites, `@MainActor`) and `SiteCycleWatch/CLAUDE.md` (thin-client transport rules).
- Turn the "known bug" and `progressColor` notes into GitHub issues.
- Delete `CI.md`, the three disabled workflows, `ExportOptions.plist` and `docs/testflight-setup.md`; git history is the rollback.
- Optionally add `.claude/skills/add-swift-file` and `add-setting`, and a PostToolUse hook that runs the project check after `*.swift` edits.

Example rewrite of the dedup rule:

```md
- **Dedup keepers must not depend on device.** Devices dedup before CloudKit
  syncs; different keepers mean both copies get deleted. Pick from synced
  scalars only (customized-default, isEnabled, then lowest `id`) — never fetch
  order, entry counts or `sortOrder` ties. Enforced by `DedupOrderIndependenceTests`.
```

---

## 6. Architecture, weighed

**Current shape.** Views create ViewModels in `onAppear` and refresh them by hand. ViewModels own `ModelContext` and also contain the pure algorithms as statics. Location and Problem config views write to the context directly. The UI and the watch share one write function (`logSiteChange`), but **every side effect after a write is wired per call site**:

- 9 `pushCurrentState()` calls in views
- 7 refresh triggers in `HomeView`
- a `lastWatchCommandDate` workaround

Mutation sites and their side effects:

| Mutation | Pushes to watch/widgets? | Refreshes the VM? |
|---|---|---|
| Log change (UI) | ✅ | ✅ |
| Watch command | ✅ | via the workaround |
| History edit/delete | ✅ (in the view) | `onAppear` |
| Location add/delete/move | ✅ | ✅ |
| **Location enable toggle** | ❌ (and no save) | `onAppear` |
| **Onboarding CSV restore** | ❌ | — |
| **CloudKit remote import** | ❌ | ❌ |

**Other structural issues:**

- **Layering is inverted.** The connectivity layer creates a UI ViewModel just to log a change (a full fetch and recommendation pass), and persistence rules live in views.
- **Settings are scattered.**
  - `"targetDurationHours"` is a literal in 4 files, and the default 72 appears in about 6 places.
  - Static loaders read `UserDefaults.standard` with no way to inject test values.
  - Defaults agree today, so this is a drift risk, not a current bug.
  - Settings that change how data is interpreted are per device, so an iPad and an iPhone can judge the same entries differently.
- **Duplication across targets has already diverged.**
  - `progressColor` has 4 copies, and one is already wrong (§3).
  - The display-name logic exists twice, "kept in sync" only by a comment.
  - The first 60 lines of the two widget files are byte-identical.
  - There are 5 hour formatters and 3 "days ago" helpers.
- **The domain is stringly typed.** `"left"`/`"right"` is compared in 8 places, and `side == "left" ? "L" : "R"` maps anything else to R. CSV identifies locations by display name. `zone` is a legacy string that is still used for grouping.
- **Errors are mostly silent.** About 18 `try? save()` calls, a silent decode failure on the watch, and a `print` in the container fallback.

**Three target architectures:**

| | A. Keep MVVM, fix the seams | B. A + a `SiteCycleCore` local package (**recommended destination**) | C. SwiftData-native `@Query` views |
|---|---|---|---|
| What changes | A `SiteStore` becomes the only writer. A `ChangeMonitor` watches `didSave`, CloudKit `.import` success and remote-change notifications, then pushes once (debounced) and bumps a `revision`. Typed settings registry. | A, plus Foundation-only algorithms over value snapshots (`SiteSnapshot{id, name, side, sortOrder, uses}`). `@Model` classes stay in the app. A small `SiteCycleUI` target for the ring and colours. | Views read `@Query`; ViewModels hold transient state only |
| Fixes §2.6, §2.7 and stale state | Yes | Yes | Only partly: the watch and widgets still need a monitor |
| Agent test loop | Xcode Cloud only | `swift test` on Linux and in GitHub Actions | Xcode only |
| pbxproj churn and duplication | Unchanged | Gone for core code | Unchanged |
| Cost | Low | Medium (1–3 days, plus one hour of the owner's time in Xcode) | Medium; reverses the "logic in VMs" convention |

**Recommendation: start with A, because every step fixes a real bug, and converge on B.** Use `@Query` only as a refresh *trigger* for display-only lists.

**What can move into the Core package as is.** These are already Foundation-only:

- `WatchAppState.swift`
- `DurationFormat`
- `EarlyChange`
- `RecommendationStrategy`
- `StatsTimeWindow`
- the median, percentile and anomaly maths
- the CSV field parser and escaping
- `SiteProblem.sanitizeEmoji` and `nameKey`
- the `DefaultProblems` and default-zone tables

**What needs a snapshot seam first:** `computeRecommendations` (it walks `safeEntries` inside sort comparators), `summarizeProblems`, the dedup keeper predicates, and `CSVExporter.generate`.

**Rejected alternatives:**

- **Standalone watch with its own CloudKit store.** It was tried and reverted: `6696a94` → `0092f13`. A second writer would multiply the delicate dedup rules.
- **Deterministic UUIDs for seeded defaults.** CloudKit still creates two records, because `id` is an ordinary field and not the record name. Use `defaultKey` with the lowest `id` as keeper.
- **XcodeGen or Tuist.** They add a macOS generator step for six targets and no packages; native synchronized folders are simpler.
- **Framework targets.** They add embedding and signing work and still give no Linux tests.

---

## 7. Build, CI and tooling

- **Agents have no feedback loop ✅.**
  - **What's missing here:** no `swift` or `xcodebuild`, and the network proxy refused download.swift.org and GitHub release downloads.
  - **What's visible from GitHub:** only `lint.yml`. Xcode Cloud posts a status on the PR, but logs and test failures are in App Store Connect.
  - **No merge gate:** no check is required (`docs/xcode-cloud-setup.md:111`).
  - **Fix:**
    1. Synchronized folders.
    2. `SiteCycleCore`, plus an `ubuntu-latest` `swift test` job.
    3. Optionally, `ci_scripts/ci_post_xcodebuild.sh`, which posts the `xcresulttool` failure summary as a PR comment.
    4. Allow download.swift.org and github.com in the cloud environment, and install the toolchain and SwiftLint in its setup script.
    5. Make Xcode Cloud CI, Lint (with its `paths-ignore` filter removed) and `swift test` required checks.
- **Synchronized folders.** Each target's folder already maps exactly onto its Sources phase; the one exception is the shared `WatchAppState.swift`, which becomes 3 membership exceptions. Converting means running "Convert to Folder" per group in Xcode 16+, about an hour on a Mac. **Don't hand-write it on Linux.**
  - **Until then:** correct the recipe and add `scripts/check_project.py` (stdlib only, under a second on Linux) to lint CI. It should check that IDs are unique, every `.swift` file is in its target, and the shared-file list is correct.
- **SwiftLint:**
  - `brew install swiftlint` is unpinned on a `macos-15` runner. Move it to `ubuntu-latest` with the pinned `ghcr.io/realm/swiftlint:<ver>` image, and add `swiftlint_version:`.
  - `SiteCycleUITests` is not linted; it contains `XCUIApplication!`, which the opt-in `implicitly_unwrapped_optional` rule would reject.
  - Add a `scripts/lint.sh` that uses a local binary or the Docker image.
- **Signing leftovers.** Release configs keep `PROVISIONING_PROFILE_SPECIFIER` alongside `CODE_SIGN_STYLE = Automatic` (app, watch, watch widgets), which Xcode reports as conflicting. Remove them. `ExportOptions.plist` still has bitcode keys.
- **Per-target duplication.** `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` and `DEVELOPMENT_TEAM` are repeated 8–12 times. An agent that bumps only the app version produces a mismatched upload. Move them into `SiteCycleConfig.xcconfig`, which is already the base config.
- **Warnings never fail any build.** Add `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in Debug, which the Xcode Cloud test actions use, so Xcode 27 deprecations surface.
- **`.gitignore` traps for a future package.** `Packages/` would silently ignore the conventional local-package folder. `Package.resolved` would also match the workspace copy that Xcode Cloud needs committed.
- **Scripts:**
  - `generate_icon.py` works (its output is pixel-identical) but needs Pillow, which is undocumented, and writes only the iOS icon.
  - `json_to_csv.py` is an unreferenced one-off importer.
  - Move both to `scripts/` with a one-line purpose each, or delete them.

---

## 8. iOS 27 and platform features

**Bottom line.** iOS 27 itself adds little that SiteCycle needs. The highest-value features all work on the current **iOS 18 / watchOS 11** target with no `#available` branches.

iOS 27 matters mainly as an SDK migration with a coming App Store deadline. The deadline isn't announced yet; past years point to around April 2027 (an inference). Since April 2026, uploads already need Xcode 26+.

Claims below come from the research reviewer's sources, which are mostly developer.apple.com release notes and WWDC26 session pages. I did not re-fetch them.

| Feature | Min OS | Use in SiteCycle | Value / Effort |
|---|---|---|---|
| **Time-sensitive "site due" notifications** with Log/Snooze actions | iOS 15 | The README's #1 roadmap item; schedule from the single `pushCurrentState()` hook | H / L–M |
| **App Intents + App Shortcuts** (`LogSiteChangeIntent`, `CurrentSiteIntent`, `LocationEntity`) | iOS 16 | Siri, Shortcuts, Spotlight, Action button | H / M |
| **Control Center / Lock Screen control** (`ControlWidget`) | iOS 18 (watchOS 26) | One-tap "Log Site Change" | M–H / L once intents exist |
| **Widget deep link / interactive button** | iOS 17 | Open site selection from the widget | M / L |
| **Live Activity for the last ≤8h before target** | iOS 16.1; scheduled start iOS 26; Watch/CarPlay `.small` iOS 26 | "Change due in 2h 10m" (Live Activities can't run for 72h) | M–H / M |
| **Refresh after CloudKit import**; `HistoryObserver` | iOS 18 hook; `HistoryObserver` iOS 27 | Fixes the stale-state bugs in §3 | M / L |
| **`transferCurrentComplicationUserInfo`** | Per the watchOS 27 release notes, now works for WidgetKit complications | Immediate watch-face updates | M / L |
| **Tinted/clear widget rendering fallback** | iOS 26 Home Screen modes | The heat colour becomes monochrome; add a symbol or text for due/overdue | M / L |
| **watchOS Smart Stack relevance widget** | watchOS 26 | Surface the widget near the target time | M / M |
| **String Catalog** (Xcode 27 can draft translations) | build-time | The app is English-only, with plural bugs | M / L–M |
| Low value: Foundation Models, HealthKit (`insulinDelivery` records units, not sites), AlarmKit, App Schemas | — | Nothing compelling | L |
| Liquid Glass | automatic with the 26/27 SDK | Standard components, no opt-out set, nothing fighting it | none needed |

**Deployment target.** **Stay on iOS 18.0 / watchOS 11.0, and build with Xcode 27.**

- iOS 26 and 27 run on the same iPhones. Moving to 26 would cut off XS/XR hardware and users who delay updates; pump users plausibly wait for vendor approval.
- watchOS 27 drops Series 6–8, SE 2 and the original Ultra.
- Move to 26/26 in the first release after iOS 28 ships. Add the CLAUDE.md rule: *"no `#available` branches; a feature must work at the deployment target, or the target is raised"*, because CI never exercises the old-OS branch.

**Check on the first Xcode 27 build** (per the iOS 27 release notes):

- `@State` becomes a macro with documented source breaks. Four views use `_x = State(initialValue:)`.
- `TabView` now crashes if its selection points at a hidden tab. Onboarding uses a paged `TabView` with a selection.
- Fix soft deprecations: `.navigationBarLeading/Trailing` → `.topBarLeading/Trailing`, `.alert(item:){ Alert }`, and `Text +` concatenation.
- Replace the UIKit document-picker and share-sheet wrappers with `.fileImporter` and `ShareLink`.

**Top 5 adoptions:**

1. Reminders
2. App Intents
3. Control and widget entry points
4. Sync freshness
5. End-of-wear Live Activity

---

## 9. Needs a device or account to confirm

1. **Store location before and after PR #70** (§2.4). This is the most urgent.
2. **Watch error-handler crash** (§2.5): force-quit the iPhone app, then log a change from the watch.
3. **WCSession when the phone app is launched in the background** (§2.6).
4. **Onboarding crash** (§2.5): does Welcome → Configure crash with the environment fix in place?
5. **CloudKit Console:** is the `SiteProblem` record type and its many-to-many relationship deployed to Production?
6. **App Store Connect email** for ITMS-91053 (privacy manifest).
7. **A local Release archive** with conflicting provisioning settings (§7).
8. **The Xcode 27 `@State` and `TabView` changes** (§8).

## 10. Suggested PR sequence

Each step ships on its own.

1. **Data-safety PR.** §2.1 CSV validate-then-replace and onboarding confirmation; §2.2 location keeper, `isEnabled` merge and migrate/dedup order; tests T1, T3, T5, T6.
2. **Crash PR.** §2.5 range clamp, `DurationFormat`, onboarding environment injection; tests T2 and the History validation tests.
3. **Watch command PR.** §2.6 `WatchCommandApplier`, early activation, nonisolated error handler; T14.
4. **Single-active-entry PR.** §2.7 close all open entries, repair pass, `EntryDraft` diffing (§3); T7, T8, T11.
5. **Repo hygiene PR.** Stale-branch workflow safety, privacy manifests, signing leftovers, versions into the xcconfig, SwiftLint pin and UI-test inclusion, `scripts/check_project.py`, delete the dead workflows and CI.md, fix README and custom-bundle-id.md.
6. **CLAUDE.md rewrite** (§5), with nested CLAUDE.md files and `TestSupport.swift`.
7. **Owner, in Xcode.** Convert to synchronized folders.
8. **`SiteStore` + `ChangeMonitor` + typed `AppSettings`.** Delete the view-level push calls and the `lastWatchCommandDate` workaround.
9. **`SiteCycleCore` phase 1.** Pure maths, formatting, `WatchAppState`, CSV parsing; Linux `swift test` job; make the checks required.
10. **`SiteCycleCore` phase 2** (recommendation engine behind snapshots) and **`SiteCycleUI`** (one ring and colour implementation for 4 targets).
11. **Features.** Reminders → App Intents → Control/widget link → complication push → Live Activity.
