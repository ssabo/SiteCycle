# Architecture

This doc explains how the iOS app's pieces fit and *why* they behave the way they do. Rules agents must follow are in [`CLAUDE.md`](../CLAUDE.md). The watch, connectivity and widgets are in [`watch-and-widgets.md`](watch-and-widgets.md). Known bugs are listed in [`reviews/2026-11-12-adversarial-review.md`](reviews/2026-11-12-adversarial-review.md) and flagged below with **Known issue**.

Keep this doc factual. When the code changes how something below works, update it in the same PR.

## Shape of the app

- **Pattern:** MVVM.
  - Views create their ViewModel in `onAppear`, from the environment's `modelContext`, and refresh it by hand: on appear, on sheet dismissal, on settings `onChange`, and when `PhoneConnectivityManager.lastWatchCommandDate` changes.
  - ViewModels are `@MainActor @Observable`. They hold the `ModelContext`, and they contain the pure algorithms as `static` functions, so those algorithms can be tested with plain model objects.
- **Navigation:**
  - A `TabView` with three tabs: Home, History and Statistics.
  - Settings opens from a gear button in the navigation bar.
  - Logging a site change is a sheet presented from Home: `SiteSelectionSheet` → `SiteChangeConfirmationSheet`.
- **Writes:**
  - Site changes go through `SiteChangeViewModel.logSiteChange`, used by both the UI and watch commands.
  - History edits go through `HistoryViewModel`.
  - `LocationConfigView` and `ProblemConfigView` write to the context directly.
  - After a write, the caller must call `PhoneConnectivityManager.pushCurrentState()` (CLAUDE.md rule 7).
  - **Known issue:** nothing refreshes Views, the watch or widgets after a CloudKit import from another device.

## Data model (SwiftData, `SiteCycle/Models/`)

All three `@Model`s follow CloudKit's rules: every property is optional or defaulted, and every relationship is optional, has an inverse and nullifies on delete.

### `Location`

A body site.

- **Fields:**
  - `id`
  - `bodyPart` (e.g. "Abdomen")
  - `subArea` (optional, e.g. "Front")
  - `side` (optional, `"left"` or `"right"`)
  - `isEnabled`
  - `isCustom`
  - `sortOrder`
  - `zone`: a legacy derived string, `"<subArea> <bodyPart>"`, still used as the grouping key in `LocationConfigView`.
- **Display names:**
  - `displayName` is `"Abdomen (Front)"`.
  - `fullDisplayName` adds the side: `"L Abdomen (Front)"`.
  - `LocationInfo` in `WatchAppState.swift` duplicates this naming logic for the watch, and the two must match.
- **Side:** only `"left"` maps to "L"; any other non-nil value shows as "R".

### `SiteChangeEntry`

One site's wear period.

- **Fields:**
  - `startTime`
  - `endTime` (nil while the site is active)
  - `note`
  - `location`
  - `problems`
- **Derived values:**
  - `durationHours`: nil while the entry is active.
  - `safeProblems`: the problems sorted by `sortOrder`.
- `SiteChangeEntry.fetchActive(in:)` returns the newest entry whose `endTime` is nil.
- **Known issue:** nothing enforces a single active entry.

### `SiteProblem`

A reason a site was changed early.

- **Fields:**
  - `id`
  - `name`
  - `emoji`
  - `isEnabled`
  - `isCustom`
  - `sortOrder`
  - `defaultKey`: a stable key for seeded defaults; nil for custom problems.
- Many-to-many with `SiteChangeEntry`.

## Launch sequence

`SiteCycleApp.makeModelContainer()` tries CloudKit (`.automatic`) first and falls back to a local store (`.none`). The fallback exists for unsigned CI; see CLAUDE.md rule 2. The `-uiTestMode` launch argument forces an in-memory store with no CloudKit.

The first time `ContentView` appears, `SiteCycleApp` calls `StoreMaintenanceCoordinator.start`, then `PhoneConnectivityManager.configure(modelContext:)` and `pushCurrentState()`. Later appearances don't re-run maintenance.

### Store maintenance

`prepareStore(context:)` runs once per launch, before any screen holds a record:

1. `migrateLocationBodyParts`: fills `bodyPart` and `subArea` from the legacy `zone` string. It must run before location dedup: unmigrated rows all share an empty `bodyPart`, so dedup skips them rather than merging every legacy left site into one.
2. `deduplicateLocations`:
   - **Groups:** non-custom locations with the same `(bodyPart, subArea, side)`. Defaults can't be renamed, so these fields identify a default as `defaultKey` does for problems.
   - **Keeper:** the lowest `id`.
   - **Merge:** entries on the duplicates are moved onto the keeper. The user's settings are judged against how each copy was seeded, and copied onto the keeper:
     - `isEnabled`: a disabled copy wins, because defaults are always seeded enabled.
     - `sortOrder`: the keeper's if it differs from its seeded index (the user moved it, or a CSV restore renumbered it), otherwise the first such duplicate's. The seeded index is the position in `DefaultLocations.all`, so that list is append-only.
3. `deduplicateSiteChangeEntries`: merges entries with the same start, end, location and note. The keeper is the lowest `id`, and the duplicates' problems are merged into it. It runs after location dedup, because two copies of an entry match only once both point at the location keeper.
4. `deduplicateProblems`:
   - **Groups:** defaults are grouped by `defaultKey`, and custom problems by `SiteProblem.nameKey` (trimmed and lowercased).
   - **Keeper:** a customized default comes first, meaning one that is renamed, has a new emoji, is disabled, or has moved from its seeded index. Next comes an enabled custom problem, then the lowest `id`.
   - **Merge:** entries on the duplicates are moved onto the keeper.

`seedStore(context:)` adds the defaults the store doesn't have:

- `seedDefaultLocations`: the 14 locations in `DefaultLocations.all` (7 zones × left/right), each seeded with its index as `sortOrder`. It seeds whenever the store has no default locations, so a custom zone added first doesn't block them; custom zones move after the defaults.
- `seedDefaultProblems`: inserts every default whose `defaultKey` is missing, so a default added in a later version reaches existing users.

#### When seeding runs

- **Local-only store:** at launch, before `prepareStore`.
- **iCloud store:** after the first successful CloudKit import, or 10 seconds after launch if none succeeds (offline, no iCloud account). Home then refreshes, and the watch and widgets are updated.
  - **Why:** a new phone that seeded at launch would get its own copy of every default. Merging those with the user's real ones, which a later launch does, can delete the copy whose history hasn't downloaded yet, and those entries lose their location on every device (review §2.3). Seeding after the download means a new phone finds the user's sites and creates no duplicates.
  - **Cost:** a brand-new user sees an empty site list for a few seconds at first launch. Onboarding's list is a live `@Query`, so it fills in when seeding runs.

Duplicates still come from two devices seeding at the same time, or adding the same custom problem, before CloudKit has synced. They are merged at the next launch.

`@AppStorage("hasCompletedOnboarding")` controls the onboarding cover. It is stored per device, so onboarding appears again on every new device or reinstall.

## Recommendation engine

`SiteChangeViewModel.computeRecommendations(locations:strategy:cooldownCount:)` is a pure static function that takes enabled locations. Callers read the settings through `RecommendationStrategy.load()` and `loadCooldownCount()`. The callers are `SiteChangeViewModel.refresh()` and `PhoneConnectivityManager.buildWatchAppState`.

It returns three lists.

### `avoid`

The 3 most recently used individual sites, by latest `startTime`, including the active one. This list works the same way in every strategy.

### `recommended`

Up to 3 sites, never overlapping with `avoid`. Never-used sites count as the oldest, so they are recommended until they have been used. How the 3 are chosen depends on `RecommendationStrategy`. The setting key is `"recommendationStrategy"` and the default is `bySite`.

- **By Site:** the 3 least recently used sites.
  - Never-used ties currently resolve to the *highest* `sortOrder` first. The other two strategies resolve ties by the lowest.
- **By Body Part:**
  - **Grouping:** sites are grouped by `(bodyPart, side)`. A group's recency is the *most* recent use of any of its sites; never-used groups count as oldest.
  - **Selection:** take the 3 least recently used groups, then the least recently used site within each, with never-used sites first and ties broken by lowest `sortOrder`.
  - **Why:** this gives the whole body part a rest. It prevents "L Thigh (Front)" straight after "L Thigh (Side)", which By Site allows.
- **Body Part Cooldown:**
  - **Ordering:** least recently used per site. Any site whose `(bodyPart, side)` group appears in the last N site changes ("hot") sorts below every site from a "cool" group.
  - **Setting:** the key is `"bodyPartCooldownCount"`; the default is 2 and the range 1–10. Its stepper only appears in Settings when this strategy is selected.
  - **Hot sites** are moved down the list, never excluded, so when every group is hot the order is plain least recently used.
  - A never-used site in a hot group sorts below used sites from cool groups, because the hot/cool split takes priority over the never-used-first rule.
  - **Why:** By Body Part rotates *groups* evenly, so a body part with one site gets used three times as often per site as a body part with three sites. Cooldown keeps the rest period without that overuse.

**Known issue:** with 3 or fewer enabled sites, `avoid` takes all of them and `recommended` is empty, in every strategy.

### `allSorted`

Every enabled location in `sortOrder`, with left before right within a zone. The **All Locations** section of the site picker uses this list, with an orange warning badge on `avoid` sites and a green check on `recommended` ones.

## Logging a site change

`SiteChangeViewModel.logSiteChange(location:note:previousNote:previousProblems:previousEntry:changeTime:)`:

1. **Closes the active entry.** It sets the active entry's `endTime` to `changeTime`, which defaults to now.
   - Only the newest open entry is closed.
   - The confirmation sheet's time picker lets the user backdate the change, but not to before the previous site started.
2. **Updates the closing site.** It applies the note and problem edits to `previousEntry`, the entry the sheet showed. If that is nil, it uses the active entry.
   - This matters because a watch command may have logged a change while the sheet was open.
   - It writes only values that differ, and it skips an entry that was deleted while the sheet was open.
3. **Records the new site.** It inserts the new entry and saves.

### The confirmation sheet

- **Layout:** the "Closing" section comes right after Time. It shows the closing site, its duration ("31h of 72h"), problem chips and a note for that site.
- **Early changes:** a site counts as early when `EarlyChange.isEarly` says it lasted less than a percentage of the target duration. The setting is `"earlyChangeThresholdPercent"`; the default is 75, adjustable in steps of 5.
  - If the site was early, the header reads "Closing · Changed Early?" and the chips are visible.
  - Otherwise the chips sit behind a "Record a Problem" button, so routine changes stay quick.
  - Once the chips are shown, they stay shown for the rest of that sheet.
- **Edits sent:** the sheet is meant to send `.replace` only for values the user edited.
  - **Known issue:** it compares against the *live* entry instead of the values it showed, so an edit synced in from another device can be overwritten. `HistoryEditView` has the same problem.
- **Durations** on the sheet and in History use `DurationFormat.hoursMinutes` ("31h 24m"). Statistics uses one decimal place ("31.4h") for aggregates.

## Site problems

- **Defaults** (`DefaultProblems.all`): Painful 🤕, Leaking 💧, Fell Off / Ripped Off 🩹, Occlusion 🚫, Unexplained Highs 📈, Bleeding 🩸.
- **Managing them** happens in Settings → Manage Problems (`ProblemConfigView`): rename, change emoji, enable or disable, reorder, and add custom problems.
  - Defaults can only be disabled, never deleted.
  - Custom problems with history are soft-deleted; those without history are hard-deleted.
- **Validation:**
  - `SiteProblem.nameError` requires a name that is non-empty, unique ignoring case (via `nameKey`) and free of `;` (`csvSeparator`), because CSV identifies problems by name.
  - `sanitizeEmoji` keeps only the last emoji typed.
  - An empty emoji is displayed as `fallbackEmoji`.
- **Picking problems:** `ProblemChips` is a multi-select chip grid, shared by the confirmation sheet and `HistoryEditView`. It shows enabled problems plus the entry's original problems, even if those are disabled.
- **History:**
  - Rows show every problem's emoji.
  - `HistoryViewModel.setProblems` edits them.
  - `HistoryProblemFilter` (all / any problem / a specific problem) sits next to the location and date filters.

## Statistics

### Time window

The Statistics tab has a time-window picker: All / 9mo / 3mo / 1mo / 14d (`StatsTimeWindow`, key `"statisticsTimeWindow"`).

- An entry counts if its `startTime` falls in the window. Months are calendar months.
- Counts, durations, usage distribution and absorption flags respect the window.
- Last used and site rest time always use full history.
  - **Known issue:** rest time is measured from the site's last `startTime`, not its `endTime`.

### Duration statistics

- **Skipped entries:** median and percentile always skip the active site, and they pass through `filterAnomalies` first.
- **What `filterAnomalies` drops:** every site under 12h, plus anything below Q1 − 1.5·IQR once there are at least 4 samples.
  - **Known issue:** this drops exactly the early failures that P25 is meant to show.
- **Shared helpers:** `StatisticsViewModel.summarize(_:)` and `completedDurations(of:since:)`.
- **The percentile is P25** (`durationPercentile`):
  - **Why not P10:** sites are changed every 1.5–3 days, so a 14-day window holds only about 5–9 sites, and P10 would collapse to the minimum.
  - **What it means:** P25 stays stable and reads as "1 in 4 sites ended before X".
  - It is omitted below 4 samples.
- **Home badge:** Home shows a `QuickStatBadge` with the median or P25 (`"homeStatMetric"`) over a window (`"homeStatTimeWindow"`, default 1mo). `HomeViewModel.refreshQuickStat()` computes it with the same helpers, so it matches the Statistics tab.

### Problems

- **Where it's computed:** `StatisticsViewModel.summarizeProblems` produces the any-problem rate and per-problem counts for the window.
- **Counting:** a site with several problems counts once toward "any" and once toward each of its problems.
- **Denominator:** completed sites, plus the active site only if it already has a problem.
- **Per location:** each location shows a rate and a breakdown, e.g. "Problems: 3 of 9 · 33%  💧2 🤕1". A rate is used because locations are used different numbers of times.

## Settings

Settings live in UserDefaults via `@AppStorage`. They are stored per device, not synced.

| Key | Default | Defined by |
|---|---|---|
| `targetDurationHours` | 72 (12–168, steps of 6) | string literal (`SettingsView`, `HomeView`, `SiteChangeConfirmationSheet`, `PhoneConnectivityManager`) |
| `earlyChangeThresholdPercent` | 75 (5–95, steps of 5) | `EarlyChange.thresholdPercentKey` |
| `absorptionAlertThreshold` | 20 (5–50, steps of 5) | string literal (`SettingsView`, `StatisticsView`) |
| `recommendationStrategy` | `bySite` | `RecommendationStrategy.storageKey` |
| `bodyPartCooldownCount` | 2 (1–10) | `RecommendationStrategy.cooldownCountKey` |
| `statisticsTimeWindow` | `allTime` | `StatsTimeWindow.statisticsStorageKey` |
| `homeStatMetric` | `median` | `HomeStatMetric.storageKey` |
| `homeStatTimeWindow` | `oneMonth` | `StatsTimeWindow.homeStatStorageKey` |
| `watchShowAllLocations` | true | `WatchConnectivityConstants.showAllLocationsKey` |
| `hasCompletedOnboarding` | false | string literal (`SiteCycleApp`, `OnboardingView`) |

## CSV export and import

### Export

`CSVExporter.generate` writes one row per entry, with the header `date,location,duration_hours,note`.

- `date` is in ISO 8601 UTC.
- `duration_hours` has one decimal place and is empty for the active site.
- A trailing `problems` column (names joined by `;`) is added only when some entry has a problem, so problem-free exports still import into older app versions.

### Import

Import **replaces all entries and locations**, and CloudKit syncs that to every device. So nothing is deleted until the whole file has been validated and the user has confirmed. Settings ("Import Data from CSV") and onboarding ("Restore from CSV backup") share the same flow, `CSVImportViewModel`, which holds only the flow's state and takes the `ModelContext` per call.

1. **Validate.** After the file is picked, `CSVImporter.makePlan` parses every row into values (an `ImportPlan`) without touching the store. If the header is wrong or no row is valid, it throws, and the alert lists the first bad rows.
2. **Confirm.** The confirmation says how many entries the file holds and which rows will be skipped, and only then offers to replace the data.
3. **Replace.** `CSVImporter.apply` deletes the old entries and locations and inserts the new ones in a single save. It saves any unrelated pending edits first, so that on an error it can `rollback()` and leave the store as it was.

- **Rows that are skipped:**
  - fewer than 4 columns
  - a date that isn't ISO 8601, or that is more than 5 minutes in the future (an active site that starts in the future breaks the next site change)
  - a duration that is neither empty nor a number from 0 to 10 years. An empty duration means the active site, so a damaged one such as "72h" is skipped rather than imported as active, and "1e300" can't reach duration formatting.
- **Blank lines** are ignored rather than reported as skipped rows.
- **A blank location** imports as an entry with no location. The exporter writes one for an entry whose location was lost.
- **Onboarding refuses to restore over existing history.** Onboarding appears on every new device and reinstall, often while iCloud is still downloading the user's history. So if the device already has any entries, both when the button is tapped and again on confirm, it explains and points to Settings instead. Its confirmation also tells iCloud users to skip rather than restore.
- **Headers:** it accepts the header with or without `problems`. Column 5 is read only when the header declares it.
- **Locations** are recreated from their display names.
- **Problems** are kept, because they are configuration rather than history. Names are matched ignoring case, and unknown names are created as custom problems.
