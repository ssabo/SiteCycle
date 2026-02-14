# SiteCycle Implementation Plan

This plan breaks the SiteCycle spec into 6 phases. Each phase is designed to be implementable in a single Claude Code session. Phases build on each other sequentially -- each assumes the prior phase is complete.

Reference: [SPEC.md](./SPEC.md)

---

## Phase 1: Project Scaffold, Data Models & App Shell

**Goal:** Create the Xcode project, define all SwiftData models with CloudKit-ready configuration, seed default locations, and set up the tab-based navigation shell.

### Deliverables

1. **Xcode project creation**
   - Create a new SwiftUI App project named `SiteCycle` targeting iOS 17.0+.
   - Configure the project with a CloudKit container identifier (`iCloud.com.sitecycle.app`) in entitlements.
   - Add the Background Modes and iCloud (CloudKit) capabilities.
   - Set up the folder structure: `Models/`, `ViewModels/`, `Views/`, `Utilities/`.

2. **SwiftData models** (see Spec sections 3.2.1, 3.3.1, 4.3)
   - `Models/Location.swift` -- SwiftData `@Model` class:
     - `id: UUID`, `zone: String`, `side: String?` (values: `"left"`, `"right"`, or `nil`), `isEnabled: Bool`, `isCustom: Bool`, `sortOrder: Int`.
     - Computed `displayName: String` -- e.g., "Left Front Abdomen" or just "Lower Back" if no side.
     - Relationship: `entries: [SiteChangeEntry]` (one-to-many, cascade delete rule on the inverse is nullify).
   - `Models/SiteChangeEntry.swift` -- SwiftData `@Model` class:
     - `id: UUID`, `startTime: Date`, `endTime: Date?`, `note: String?`.
     - Relationship: `location: Location?` (many-to-one).
     - Computed `durationHours: Double?` -- returns `nil` if `endTime` is nil.
   - Define a `VersionedSchema` (v1) so future migrations are straightforward (Spec section 4.4).

3. **Default locations seed data** (see Spec section 3.2.2)
   - `Utilities/DefaultLocations.swift` -- A function `seedDefaultLocations(context:)` that checks if locations exist and, if not, inserts the 7 default zones (each with left/right variants = 14 locations total). All enabled by default, `isCustom = false`.

4. **App entry point & ModelContainer**
   - `SiteCycleApp.swift` -- Configure `ModelContainer` for both models with CloudKit configuration. Call seed function on first launch.
   - Store a `hasCompletedOnboarding` flag in `@AppStorage` (UserDefaults) to control first-launch flow (actual onboarding UI is Phase 2).

5. **Tab bar navigation shell**
   - `Views/ContentView.swift` -- `TabView` with three tabs: Home, History, Statistics. Each tab shows a placeholder view with the tab name and SF Symbol icon (`house`, `clock`, `chart.bar`).
   - Gear icon in the navigation bar leading to a placeholder Settings screen.

### Files Created/Modified
- `SiteCycle/SiteCycleApp.swift`
- `SiteCycle/Models/Location.swift`
- `SiteCycle/Models/SiteChangeEntry.swift`
- `SiteCycle/Utilities/DefaultLocations.swift`
- `SiteCycle/Views/ContentView.swift`

### Verification
- Project builds without errors.
- Running in Simulator shows three-tab layout with placeholder content.
- Default locations are seeded into SwiftData on first launch (verify via debug print or breakpoint).

---

## Phase 2: Location Configuration & Onboarding

**Goal:** Build the location management screen and the first-launch onboarding flow so users can configure their body locations before they start logging.

### Prerequisites
- Phase 1 complete (models, seed data, tab shell).

### Deliverables

1. **Location configuration screen** (Spec sections 3.2, 7)
   - `Views/LocationConfigView.swift`:
     - List all locations grouped by zone, showing enabled/disabled state as toggles.
     - Each zone row shows the zone name and a toggle. For zones with laterality, toggling the zone toggles both left and right locations together.
     - "Add Custom Zone" button at the bottom: presents a sheet with a text field for zone name and a laterality toggle. On save, creates 1 or 2 Location records (`isCustom = true`).
     - Swipe-to-delete on custom zones (soft-delete: sets `isEnabled = false` if the zone has history, hard-delete if no history).
     - Reorder support via `EditButton` / move handles to change `sortOrder`.

2. **Settings screen** (Spec section 7)
   - `Views/SettingsView.swift`:
     - "Manage Locations" row -> navigates to `LocationConfigView`.
     - "Target Duration" row -> stepper or picker, value stored in `@AppStorage` (default: 72 hours).
     - "Absorption Alert Threshold" row -> stepper or picker, percentage stored in `@AppStorage` (default: 20%).
     - "Export Data" row -> placeholder (implemented in Phase 6).
     - "About" row -> app version display.
   - Settings accessible via gear icon in navigation bar on each tab.

3. **Onboarding flow** (Spec section 8)
   - `Views/OnboardingView.swift`:
     - **Page 1 -- Welcome:** App name, brief description, SF Symbol illustration, "Get Started" button.
     - **Page 2 -- Configure Locations:** Embedded `LocationConfigView` (or a simplified version) letting the user toggle zones on/off. "Next" button.
     - **Page 3 -- Ready:** "Log your first site change" prompt with a "Done" button.
     - On completion, set `hasCompletedOnboarding = true` in `@AppStorage`.
   - `SiteCycleApp.swift` updated: if `!hasCompletedOnboarding`, show `OnboardingView` as a full-screen cover instead of the main `ContentView`.
   - Onboarding is skippable (skip button in nav bar) -- sets flag and proceeds to main app.

### Files Created/Modified
- `SiteCycle/Views/LocationConfigView.swift` (new)
- `SiteCycle/Views/SettingsView.swift` (new)
- `SiteCycle/Views/OnboardingView.swift` (new)
- `SiteCycle/Views/ContentView.swift` (add settings navigation)
- `SiteCycle/SiteCycleApp.swift` (onboarding gate)

### Verification
- First launch shows onboarding flow. User can toggle locations and complete onboarding.
- After onboarding, subsequent launches go directly to main tab view.
- Settings -> Manage Locations allows toggling, adding custom zones, and reordering.
- Deleting a custom zone with no history removes it; with history it disables it.

---

## Phase 3: Home Screen & Site Change Logging

**Goal:** Implement the core user flow -- the home screen showing current site status, and the site selection sheet with recommendation logic.

### Prerequisites
- Phase 2 complete (locations are configured and persisted).

### Deliverables

1. **Home ViewModel** (Spec section 5.2)
   - `ViewModels/HomeViewModel.swift`:
     - Query the most recent `SiteChangeEntry` where `endTime == nil` to find the current active site.
     - Compute elapsed hours since `startTime`.
     - Compute progress fraction: `elapsedHours / targetDuration` (target from `@AppStorage`, default 72).
     - Expose: `currentLocation: Location?`, `startTime: Date?`, `elapsedHours: Double`, `progressFraction: Double`, `hasActiveSite: Bool`.

2. **Home screen UI** (Spec section 5.2)
   - `Views/HomeView.swift`:
     - If no active site: empty state with illustration and "Log Your First Site Change" button.
     - If active site: display location `displayName`, start time formatted, elapsed hours, and a circular progress ring (using SwiftUI `Canvas` or `ProgressView` with `circularStyle` and custom gauge).
     - Color the progress ring: green < 80% of target, yellow 80-100%, red > 100%.
     - Large prominent "Log Site Change" button at the bottom.
     - Tapping the button presents `SiteSelectionSheet` as a `.sheet`.

3. **Recommendation engine** (Spec section 3.1.2)
   - `ViewModels/SiteChangeViewModel.swift`:
     - Fetch all enabled locations.
     - For each location, find its most recent `SiteChangeEntry.startTime`.
     - Sort locations by most-recent-use descending. Locations never used sort to the end (treated as oldest).
     - **Avoid list:** First 3 locations (most recently used). If fewer than 3 locations have been used, only include those that have been used.
     - **Recommended list:** Last 3 locations (least recently used / never used). Must not overlap with Avoid list.
     - Handle edge cases: fewer than 6 locations, all locations never used, etc.
     - Method: `logSiteChange(location:note:)` -- creates a new `SiteChangeEntry` with `startTime = now`, closes the previous active entry by setting its `endTime = now`.

4. **Site selection sheet UI** (Spec section 5.3)
   - `Views/SiteSelectionSheet.swift`:
     - Three sections in a `List` or `ScrollView`:
       - **Avoid** section (red/orange header): shows avoid locations with warning icon (SF Symbol `exclamationmark.triangle.fill`), last-used date.
       - **Recommended** section (green header): shows recommended locations with checkmark icon (SF Symbol `checkmark.circle.fill`), last-used date or "Never used".
       - **All Locations** section: alphabetical, each showing last-used date. Locations in Avoid/Recommended are tagged with a small colored badge.
     - Tapping a location shows a confirmation view/alert:
       - Displays selected location name.
       - Optional note `TextField`.
       - "Confirm" and "Cancel" buttons.
     - On confirm: calls `logSiteChange()`, dismisses sheet.

### Files Created/Modified
- `SiteCycle/ViewModels/HomeViewModel.swift` (new)
- `SiteCycle/ViewModels/SiteChangeViewModel.swift` (new)
- `SiteCycle/Views/HomeView.swift` (new, replaces placeholder)
- `SiteCycle/Views/SiteSelectionSheet.swift` (new)

### Verification
- Home screen shows empty state on first launch (after onboarding).
- Tapping "Log Site Change" opens the sheet with Recommended section populated (all locations are "never used" initially).
- Selecting a location and confirming logs it. Home screen updates to show current site with elapsed time.
- Logging a second change closes the first entry (verify `endTime` is set).
- Avoid/Recommended lists update correctly after several site changes.

---

## Phase 4: History View

**Goal:** Build the history tab with a full chronological log, filtering, and the ability to edit/delete entries.

### Prerequisites
- Phase 3 complete (site changes are being logged).

### Deliverables

1. **History ViewModel** (Spec section 3.3.2)
   - `ViewModels/HistoryViewModel.swift`:
     - Query all `SiteChangeEntry` records sorted by `startTime` descending.
     - Filter by location: optional `Location?` filter. When set, only show entries for that location.
     - Filter by date range: optional `startDate` / `endDate`. When set, only show entries within range.
     - Delete entry: remove the `SiteChangeEntry`. If it was the most recent entry and the one before it had its `endTime` set to this entry's `startTime`, reopen the previous entry (set `endTime = nil`) -- or simply delete without adjusting (simpler; note this in the UI).
     - Edit entry: update location, startTime, endTime, and note fields on an existing entry.

2. **History list UI** (Spec section 3.3.2)
   - `Views/HistoryView.swift`:
     - `List` displaying entries in reverse chronological order.
     - Each row shows:
       - Location `displayName`.
       - Start date/time (formatted: e.g., "Feb 7, 2026 at 3:15 PM").
       - Duration (e.g., "68.5 hours") or "Active" if `endTime` is nil.
       - Note preview (truncated if long), with note icon if present.
     - Filter controls at the top:
       - Location picker (dropdown/menu of all locations + "All").
       - Date range picker (predefined: "Last 7 days", "Last 30 days", "Last 90 days", "All Time", or custom date range).
     - Swipe-to-delete with confirmation.
     - Tap on entry navigates to edit view.

3. **History entry edit view**
   - `Views/HistoryEditView.swift` (or inline sheet):
     - `Picker` for location (all configured locations).
     - `DatePicker` for start time.
     - `DatePicker` for end time (optional, clearable).
     - `TextField` for note.
     - Save and Cancel buttons.

### Files Created/Modified
- `SiteCycle/ViewModels/HistoryViewModel.swift` (new)
- `SiteCycle/Views/HistoryView.swift` (new, replaces placeholder)
- `SiteCycle/Views/HistoryEditView.swift` (new)

### Verification
- History tab shows all logged site changes in reverse chronological order.
- Filtering by location works -- only entries for selected location appear.
- Filtering by date range works -- "Last 7 days", "Last 30 days", etc.
- Editing an entry changes persisted values.
- Deleting an entry removes it from the list and from persistence.
- Active entry (no end time) shows "Active" instead of duration.

---

## Phase 5: Statistics & Charts

**Goal:** Build the statistics tab with per-location analytics, absorption insights, usage distribution chart, and rotation timeline.

### Prerequisites
- Phase 4 complete (history entries exist and are browsable).

### Deliverables

1. **Statistics ViewModel** (Spec sections 3.4.1 - 3.4.4)
   - `ViewModels/StatisticsViewModel.swift`:
     - Compute per-location stats for all enabled locations:
       - `totalUses: Int` -- count of `SiteChangeEntry` for this location.
       - `averageDuration: Double?` -- mean of `durationHours` for completed entries.
       - `medianDuration: Double?` -- median of `durationHours` for completed entries.
       - `minDuration: Double?` / `maxDuration: Double?` -- range.
       - `lastUsed: Date?` -- most recent `startTime`.
       - `daysSinceLastUse: Int?` -- days between `lastUsed` and now.
     - Compute overall average duration across all completed entries.
     - **Absorption insight** (Spec section 3.4.2):
       - For each location, if `averageDuration < overallAverage * (1 - threshold/100)`, flag it.
       - Threshold from `@AppStorage` (default 20%).
       - Generate a message: "Average duration at this site is X% below your overall average."
     - **Usage distribution data**: array of `(locationName: String, count: Int)` for chart.
     - **Rotation timeline data**: array of `(date: Date, locationName: String, color: Color)` for the past N days.

2. **Statistics main view** (Spec section 3.4)
   - `Views/StatisticsView.swift`:
     - **Usage Distribution Chart** at the top (Spec section 3.4.3):
       - `Chart` (Swift Charts) with `BarMark` for each location. X-axis: location name (rotated labels if needed). Y-axis: usage count.
       - Color bars using a consistent palette.
     - **Per-Location Stats** below the chart:
       - `List` or grid of location cards. Each card shows: location name, total uses, avg/median/min/max duration, last used, days since last use.
       - Locations with absorption flags show a yellow/orange warning banner with the insight message (Spec section 3.4.2).
     - **Rotation Timeline** (Spec section 3.4.4):
       - Segmented control for time range: 30 / 60 / 90 days.
       - Horizontal scrollable timeline or `Chart` with `RectangleMark` showing date ranges colored by location.
       - Each block represents a site change session (startTime to endTime) colored by location.

3. **Empty state**
   - If no completed site changes exist, show a friendly message: "Log a few site changes to see your statistics."

### Files Created/Modified
- `SiteCycle/ViewModels/StatisticsViewModel.swift` (new)
- `SiteCycle/Views/StatisticsView.swift` (new, replaces placeholder)

### Verification
- Statistics tab shows usage distribution chart with correct counts per location.
- Per-location stats display all required metrics (total uses, avg, median, min, max, last used, days since).
- Absorption flags appear on locations meeting the threshold criteria.
- Rotation timeline shows colored blocks for site sessions over the selected time range.
- Empty state displays when no data exists.

---

## Phase 6: Settings Completion, CSV Export & Polish

**Goal:** Complete the settings screen, implement CSV export, add the sync status indicator, and polish accessibility and Dark Mode support.

### Prerequisites
- Phase 5 complete (all main features functional).

### Deliverables

1. **CSV Export** (Spec section 7)
   - `Utilities/CSVExporter.swift`:
     - Generate CSV string from all `SiteChangeEntry` records.
     - Columns: `date` (ISO 8601 formatted startTime), `location` (displayName), `duration_hours` (rounded to 1 decimal, or empty if active), `note` (or empty).
     - Header row: `date,location,duration_hours,note`.
     - Handle commas and quotes in notes by properly escaping CSV fields.
   - Integration in Settings:
     - "Export Data" row triggers export.
     - Use `ShareLink` or present a `UIActivityViewController` via SwiftUI to share the CSV file.
     - File named `sitecycle-export-YYYY-MM-DD.csv`.

2. **Settings completion** (Spec section 7)
   - Wire up the "Export Data" row to the CSV exporter.
   - "About" section: display app version (from bundle), brief description.
   - Ensure "Target Duration" and "Absorption Alert Threshold" values are read correctly by HomeViewModel and StatisticsViewModel respectively.

3. **Sync status indicator** (Spec section 6.2)
   - Add a small cloud icon in the navigation bar or home screen that indicates sync status.
   - Use `NSPersistentCloudKitContainer.eventChangedNotification` (or SwiftData equivalent) to detect sync events.
   - States: synced (cloud checkmark), syncing (cloud with arrow), offline (cloud with slash).
   - Keep the implementation simple -- if CloudKit events aren't easily observable in SwiftData, a simpler approach is acceptable (e.g., show cloud icon always, show slash when network is unavailable via `NWPathMonitor`).

4. **Dark Mode verification**
   - Review all views and ensure semantic colors are used throughout.
   - Avoid/Recommended indicators: use `Color.red.opacity(0.15)` / `Color.green.opacity(0.15)` backgrounds that adapt to dark mode.
   - Test and fix any hardcoded colors.

5. **Dynamic Type verification** (Spec section 5.4)
   - Ensure all text uses dynamic type styles (`.body`, `.headline`, `.caption`, etc.).
   - Verify layout doesn't break at the largest accessibility text sizes.
   - Fix any truncation or overlap issues.

6. **Edge case handling & polish**
   - First launch with no data: all screens show appropriate empty states.
   - Location with zero history: stats show "No data" instead of crashing on nil.
   - Deleting all locations: prevent user from disabling all locations (require at least 1 enabled).
   - Rapid double-tap on "Log Site Change": prevent duplicate entries.
   - Long notes: ensure text wraps/truncates appropriately in history list.

### Files Created/Modified
- `SiteCycle/Utilities/CSVExporter.swift` (new)
- `SiteCycle/Views/SettingsView.swift` (updated)
- `SiteCycle/Views/ContentView.swift` (sync indicator)
- Various view files (Dark Mode / Dynamic Type fixes as needed)

### Verification
- Export produces a valid CSV file with correct headers and data.
- Sharing the CSV file works via the share sheet.
- Settings values (target duration, threshold) are reflected in Home and Statistics screens.
- App looks correct in both Light and Dark Mode.
- App is usable at all Dynamic Type sizes without layout breakage.
- All empty states render correctly.
- No crashes when data is missing or locations are deleted.

---

## Phase 7: GitHub Actions CI/CD & TestFlight Deployment

**Goal:** Set up a GitHub Actions workflow that builds the app on every push/PR, and a release workflow that archives, signs, and uploads the app to TestFlight via App Store Connect.

### Prerequisites
- Phase 6 complete (app is feature-complete and polished).
- An Apple Developer account with App Store Connect access.
- The app's Bundle Identifier registered in App Store Connect.

### Deliverables

1. **CI workflow -- build & test on every push** (`.github/workflows/ci.yml`)
   - Trigger: `push` to any branch, `pull_request` to `main`.
   - Runner: `macos-15` (Xcode 16+).
   - Steps:
     - Check out code.
     - Select Xcode version (`sudo xcode-select -s /Applications/Xcode_16.app`).
     - Resolve Swift packages (`xcodebuild -resolvePackageDependencies`).
     - Build for iOS Simulator (`xcodebuild build -scheme SiteCycle -destination 'platform=iOS Simulator,name=iPhone 16'`).
     - Run unit tests if any exist (`xcodebuild test ...`).
   - Purpose: catch build failures and regressions early on PRs.

2. **TestFlight release workflow** (`.github/workflows/testflight.yml`)
   - Trigger: `push` of a tag matching `v*` (e.g., `v1.0.0`), or manual `workflow_dispatch`.
   - Runner: `macos-15`.
   - Steps:
     - **Check out code.**
     - **Install the Apple certificate and provisioning profile:**
       - Use a keychain-based approach: decode a base64-encoded `.p12` distribution certificate and provisioning profile from GitHub Secrets, import into a temporary keychain.
       - Required secrets:
         - `APPLE_CERTIFICATE_BASE64` -- base64-encoded `.p12` distribution certificate.
         - `APPLE_CERTIFICATE_PASSWORD` -- password for the `.p12` file.
         - `APPLE_PROVISIONING_PROFILE_BASE64` -- base64-encoded `.mobileprovision` file.
         - `APPSTORE_CONNECT_API_KEY_ID` -- App Store Connect API key ID.
         - `APPSTORE_CONNECT_API_ISSUER_ID` -- App Store Connect API issuer ID.
         - `APPSTORE_CONNECT_API_KEY_BASE64` -- base64-encoded `.p8` private key.
       - Script to decode and install:
         ```
         # Create temporary keychain
         security create-keychain -p "" build.keychain
         security default-keychain -s build.keychain
         security unlock-keychain -p "" build.keychain
         # Import certificate
         echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > cert.p12
         security import cert.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
         security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain
         # Install provisioning profile
         echo "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 --decode > profile.mobileprovision
         mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
         cp profile.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/
         ```
     - **Archive the app:**
       ```
       xcodebuild archive \
         -scheme SiteCycle \
         -archivePath $RUNNER_TEMP/SiteCycle.xcarchive \
         -destination 'generic/platform=iOS' \
         CODE_SIGN_STYLE=Manual \
         PROVISIONING_PROFILE_SPECIFIER="..." \
         CODE_SIGN_IDENTITY="Apple Distribution"
       ```
     - **Export the IPA:**
       - Create an `ExportOptions.plist` specifying `app-store` distribution method, team ID, and provisioning profile mapping.
       ```
       xcodebuild -exportArchive \
         -archivePath $RUNNER_TEMP/SiteCycle.xcarchive \
         -exportPath $RUNNER_TEMP/export \
         -exportOptionsPlist ExportOptions.plist
       ```
     - **Upload to TestFlight:**
       - Use `xcrun altool` or (preferred) `xcrun notarytool` / the App Store Connect API:
       ```
       xcrun altool --upload-app \
         -f $RUNNER_TEMP/export/SiteCycle.ipa \
         --apiKey "$APPSTORE_CONNECT_API_KEY_ID" \
         --apiIssuer "$APPSTORE_CONNECT_API_ISSUER_ID" \
         --type ios
       ```
       - Alternatively, use the `apple-actions/upload-testflight-build` GitHub Action if available.
     - **Cleanup:** Delete temporary keychain and provisioning profile.

3. **ExportOptions.plist**
   - Committed to the repo at the project root.
   - Contents:
     - `method`: `app-store`
     - `teamID`: your Apple Developer Team ID (can be templated/parameterized via secret).
     - `provisioningProfiles`: dictionary mapping bundle ID to profile name.
     - `signingCertificate`: `Apple Distribution`
     - `uploadBitcode`: `false`
     - `uploadSymbols`: `true`

4. **Documentation**
   - Add a "CI/CD" section to the project README (or a `CI.md` file) documenting:
     - How to set up the required GitHub Secrets (step-by-step for each secret).
     - How to trigger a TestFlight build (push a tag or use workflow_dispatch).
     - How to generate the App Store Connect API key from App Store Connect > Users and Access > Keys.
     - How to export the distribution certificate and provisioning profile as base64.

### Files Created/Modified
- `.github/workflows/ci.yml` (new)
- `.github/workflows/testflight.yml` (new)
- `ExportOptions.plist` (new)
- `CI.md` or README update (new/updated)

### Verification
- Push to a branch triggers the CI workflow; it checks out, builds, and passes.
- Creating a tag `v1.0.0-beta.1` triggers the TestFlight workflow.
- With valid secrets configured, the workflow archives, exports, and uploads the IPA to App Store Connect.
- The build appears in TestFlight within App Store Connect after processing.

### Required GitHub Secrets Summary

| Secret Name                          | Description                                      |
|--------------------------------------|--------------------------------------------------|
| `APPLE_CERTIFICATE_BASE64`          | Base64 `.p12` distribution certificate           |
| `APPLE_CERTIFICATE_PASSWORD`        | Password for the `.p12` file                     |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 `.mobileprovision` file                   |
| `APPSTORE_CONNECT_API_KEY_ID`       | App Store Connect API key ID                     |
| `APPSTORE_CONNECT_API_ISSUER_ID`    | App Store Connect API issuer ID                  |
| `APPSTORE_CONNECT_API_KEY_BASE64`   | Base64 `.p8` API private key                     |

---

## Phase Summary

| Phase | Focus                              | Key Files                                               |
|-------|------------------------------------|---------------------------------------------------------|
| 1     | Project scaffold & data models     | Models, DefaultLocations, ContentView, App entry point  |
| 2     | Location config & onboarding       | LocationConfigView, SettingsView, OnboardingView        |
| 3     | Home screen & site change logging  | HomeView, SiteSelectionSheet, ViewModels                |
| 4     | History view                       | HistoryView, HistoryEditView, HistoryViewModel          |
| 5     | Statistics & charts                | StatisticsView, StatisticsViewModel                     |
| 6     | CSV export, settings, polish       | CSVExporter, SettingsView, Dark Mode & accessibility     |
| 7     | CI/CD & TestFlight deployment      | GitHub Actions workflows, ExportOptions.plist, CI docs  |

Each phase produces a buildable, testable increment. Phase 1 must be completed first. Phases 2-5 each depend on the prior phase. Phase 6 depends on all previous phases. Phase 7 can be done in parallel with Phases 2-6 (only the TestFlight upload requires a working build).
