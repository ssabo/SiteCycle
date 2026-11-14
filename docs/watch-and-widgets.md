# Watch, connectivity and widgets

This doc covers how the Apple Watch app, the watch complications and the iPhone widgets get their data. Rules are in [`CLAUDE.md`](../CLAUDE.md), especially rules 5–7. Known bugs, flagged below with **Known issue**, are listed in [`reviews/2026-11-12-adversarial-review.md`](reviews/2026-11-12-adversarial-review.md) §2.5, §2.6 and §3.

## Targets

All four targets share the App Group `group.$(SITECYCLE_BUNDLE_PREFIX).app` (see their `.entitlements` files). The bundle prefix comes from `SiteCycleConfig.xcconfig` and is overridable; see [`custom-bundle-id.md`](custom-bundle-id.md).

| Target | Bundle ID (default prefix) | OS |
|---|---|---|
| SiteCycle | `com.sitecycle.app` | iOS 18+ |
| SiteCycleWatch | `com.sitecycle.app.watchkitapp` | watchOS 11+ |
| SiteCycleWatchWidgets | `com.sitecycle.app.watchkitapp.widgets` | watchOS 11+ |
| SiteCycleWidgets | `com.sitecycle.app.widgets` | iOS 18+ |

### The shared file

`SiteCycle/Connectivity/WatchAppState.swift` is compiled into all four targets. It contains:

- `WatchAppState`, the phone → watch payload
- `WatchSiteChangeCommand`, the watch → phone command
- `LocationInfo`, `ActiveSiteInfo` and `LocationCategory`
- `WatchConnectivityConstants`:
  - the payload keys
  - the iPhone's `watchShowAllLocations` setting key
  - `appGroupIdentifier`, which strips the `.watchkitapp.widgets`, `.watchkitapp` and `.widgets` suffixes from the bundle ID to get `group.<prefix>.app`

**Known issue:** that stripping uses `replacingOccurrences`, so it also changes a prefix that happens to contain one of those strings.

## Thin-client design

The iPhone is the single source of truth. The watch has no `ModelContainer`, no SwiftData and no CloudKit, and it never computes recommendations.

A standalone watch app with its own store was tried and reverted (`6696a94` → `0092f13`): a second writer brought back the duplicate-seeding problem.

| Direction | Mechanism | Payload |
|---|---|---|
| Phone → watch | `WCSession.updateApplicationContext` (latest wins) | `WatchAppState`: the active site, recommended and avoid IDs, all enabled locations as `LocationInfo`, target duration, `showAllLocations` |
| Watch → phone | `sendMessage` when the phone is reachable; `transferUserInfo` (queued, guaranteed) otherwise, or when `sendMessage` errors | `WatchSiteChangeCommand { locationId, requestedAt }` |
| Phone/watch → widgets | `WatchAppState` JSON in App Group `UserDefaults`, under the `watchAppState` key | Same `WatchAppState` |

Both managers are `@MainActor @Observable`. Their `WCSessionDelegate` methods are `nonisolated` and hop to the main actor.

### iPhone: `PhoneConnectivityManager`

#### `pushCurrentState()`

It builds the state with `buildWatchAppState` (via `SiteChangeViewModel.computeRecommendations`), then:

1. writes it to the App Group;
2. calls `WidgetCenter.shared.reloadAllTimelines()`;
3. calls `updateApplicationContext`, but only if the session is activated.

The App Group write does not depend on the watch session, so the iPhone widget updates even when no watch is paired.

#### When it's called

- at launch (`ContentView.onAppear`)
- after an iCloud store's defaults are seeded, which happens after launch (`docs/architecture.md`, "Store maintenance")
- when the scene becomes `.active`
- when session activation completes
- by the View or code that made a change, after:
  - a site change
  - a History edit
  - adding, deleting or reordering a location
  - a settings change
  - a CSV import, from Settings or onboarding

**Known issue:** it is *not* called:

- after the location on/off toggle
- after CloudKit imports changes from another device

#### `configure(modelContext:)`

This activates the session.

**Known issue:** it runs from `ContentView.onAppear`, so a background launch with no UI never activates the session.

#### Watch commands

The delegate decodes each command, and `processCommand` calls `SiteChangeViewModel.logSiteChange(location:note:)` and then pushes.

**Known issues:**

- `requestedAt` is ignored, so the change is logged at the time it arrives.
- There is no command ID, so a duplicate delivery logs twice.
- An unknown location ID is dropped silently.
- A disabled location is accepted.

### Watch: `WatchConnectivityManager`

#### Receiving state

On activation, it loads the cached App Group state, then applies `receivedApplicationContext`. On each new context, it decodes the `WatchAppState`. Then it writes the state to the App Group and reloads its complications in a deferred `Task`: doing that inside the WCSession callback triggers `_dispatch_assert_queue_fail` on watchOS (fixed in #58).

#### Sending commands

`sendSiteChangeCommand(locationId:)` sets `hasPendingCommand`. That flag clears when new state arrives, or after 10 seconds.

`sendMessage` is called with `replyHandler: nil`, because the reply-handler path crashed (#58).

**Known issue:** the `errorHandler` closure is created inside a `@MainActor` method, so it likely crashes the same way when it runs. If it does, the `transferUserInfo` fallback never runs.

### Watch UI

- **`WatchContentView`:** a horizontally paged `TabView` (`.page`), with Home on the left and the site picker on the right.
- **`WatchHomeView`:** the current site with a progress ring and elapsed time (`TimelineView`). It shows "Syncing with iPhone…" until the first state arrives.
- **`WatchSiteSelectionView`:** recommended sites first. "All Locations" appears only when `WatchAppState.showAllLocations` is true; the iPhone sets that from Settings → Watch Settings → Show All Locations (default on). Tapping a site sends a command.
- **`WatchLocationRow`:** a compact row built on `LocationInfo`.
- **ViewModels:**
  - `WatchHomeViewModel` provides `currentLocationName`, `elapsedHours()` and `progressFraction()`.
  - `WatchSiteChangeViewModel` exposes the recommendations and sends commands.

## Complications (`SiteCycleWatchWidgets`)

| Family | Shows |
|---|---|
| `accessoryRectangular` | Location name and elapsed time |
| `accessoryCircular` | Progress ring and abbreviated time |
| `accessoryInline` | `L Abdomen (Front) · 2h 15m` |

**Timeline:** the current entry plus 8 future entries, 15 minutes apart, covering 2 hours. After that the policy is `.after(+2h)`.

**Known issue:** elapsed time is calculated in advance for each entry, so it moves in 15-minute steps.

**Known issue:** the circular complication caps the progress fraction at 1.0 *before* picking its colour, so it never turns red.

**Known issue:** the iPhone never calls `transferCurrentComplicationUserInfo`, and the watch has no background task. As a result, the watch face only updates while the watch app is running.

## iPhone widgets (`SiteCycleWidgets`)

| Family | Where | Shows |
|---|---|---|
| `systemSmall` | Home Screen | Full-colour heat ring (green/yellow/red) with elapsed hours |
| `accessoryCircular` | Lock Screen, StandBy, Smart Stack | Tinted ring with abbreviated time |

- **Data:** these widgets read the same App Group `WatchAppState`; there is no separate sync path.
- **Tap:** tapping opens the app, which is the `StaticConfiguration` default; no `widgetURL` is set.
- **Colour:** the Lock Screen renders `accessoryCircular` in monochrome, so the heat colour becomes the system tint.
- **Timeline:** the same timeline provider as the complications. The first ~60 lines of the two widget files are identical.

## Duplicated code

`WatchAppState.swift` is the only shared source file, so these helpers are copied:

- **`progressColor(for:)`:** green below 80%, yellow up to 100%, red above. Copies exist in `HomeView`, `WatchHomeView` and both widget files.
- **Hour formatting:** the abbreviated and one-decimal hour formatters.
- **"Days ago" text.**
- **Display names:** `LocationInfo`'s naming logic copies `Location`'s.

If you change one copy, change all of them, or better, move the helper into the shared file or a shared package (review §6).
