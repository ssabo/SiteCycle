# Product Specification: SiteCycle

**iOS Application for Insulin Pump Users**

|              |                              |
|--------------|------------------------------|
|**Version:**  |1.0                           |
|**Date:**     |February 7, 2026              |
|**Platform:** |iOS (iPhone)                  |
|**Framework:**|SwiftUI + SwiftData / CloudKit|

-----


## 1. Overview

SiteCycle is an iOS application designed for insulin pump users to track and manage their infusion site locations. The app helps users rotate their pump sites effectively by recommending optimal placement locations based on usage history, and provides statistical analysis to identify potential absorption issues.

### 1.1 Problem Statement

Insulin pump users must regularly rotate infusion sites (typically every 2-3 days) to prevent lipohypertrophy (tissue hardening), scarring, and reduced insulin absorption. Without a systematic tracking method, users often default to the same few locations, leading to overuse of certain areas and underuse of others.

### 1.2 Solution

The app provides a simple, structured workflow: when a user changes their infusion site, they log the new location and the app provides intelligent recommendations based on rotation history. Over time, the app surfaces statistical insights about usage patterns and insulin absorption characteristics per site.

-----

## 2. Target User

The primary user is an insulin pump wearer who changes their infusion site every 2-4 days. They want a quick way to log site changes and get guidance on where to place their next site. They may use a variety of pump brands (Omnipod, Tandem, Medtronic, etc.). The app is pump-agnostic and does not integrate with pump hardware.

-----

## 3. Core Features

### 3.1 Site Change Logging

This is the primary interaction. When a user changes their pump, they open the app and log the new infusion site.

#### 3.1.1 Site Change Flow

1. User taps a primary action button (e.g., "Log Site Change") on the home screen.
2. App displays the site selection screen with three sections:
   - **Avoid** (3 most recently used locations) -- visually flagged in red/orange as locations to avoid.
   - **Recommended** (3 least recently used locations) -- visually flagged in green as best candidates.
   - **All Locations** -- complete list of the user's configured locations, each showing the date/time it was last used.
3. User selects a location. All locations are selectable regardless of recommendation status.
4. User optionally adds a note (e.g., "site felt sore", "bled on insertion").
5. User confirms. A timestamp is recorded automatically. The previous site's session is closed (end time recorded).

#### 3.1.2 Recommendation Logic

The recommendation engine is straightforward:

- **Avoid list:** The 3 locations with the most recent usage timestamps (i.e., the last 3 distinct locations used). These locations have had the least recovery time.
- **Recommended list:** The 3 locations with the oldest usage timestamps (or locations that have never been used). These locations have had the most recovery time.

If a user has fewer than 6 configured locations, the avoid and recommended lists may overlap or be smaller. The UI should handle this gracefully -- for example, if there are only 4 locations, show 3 in Avoid and 1 in Recommended with no duplicates.

If a location has never been used, it should be treated as the oldest possible timestamp for sorting purposes (i.e., it will always appear in Recommended until used).

### 3.2 Location Configuration

Users must be able to configure which body locations are available for site placement. This is a setup step (accessible at any time from settings) that personalizes the app.

#### 3.2.1 Body Location Model

Each configurable location is a combination of a body zone and an optional laterality (left/right). The data model is:

| Field         | Type   | Required | Description                                                    |
|---------------|--------|----------|----------------------------------------------------------------|
| id            | UUID   | Yes      | Unique identifier                                              |
| zone          | String | Yes      | Body zone name (e.g., "Front Abdomen")                         |
| hasLaterality | Bool   | Yes      | Whether this zone applies to left and right sides              |
| side          | Enum?  | No       | If hasLaterality is true: `.left` or `.right`. Null otherwise. |
| isEnabled     | Bool   | Yes      | Whether this location is currently active                      |
| displayName   | String | Yes      | Computed: e.g., "Left Front Abdomen" or "Lower Back"           |

#### 3.2.2 Default Locations

The app ships with a predefined set of common infusion site zones. Each zone can be toggled on or off, and laterality is applied to generate individual locations:

| Zone              | Has Laterality | Generated Locations                     |
|-------------------|----------------|-----------------------------------------|
| Front Abdomen     | Yes            | Left Front Abdomen, Right Front Abdomen |
| Side Abdomen      | Yes            | Left Side Abdomen, Right Side Abdomen   |
| Back Abdomen      | Yes            | Left Back Abdomen, Right Back Abdomen   |
| Front Leg (Thigh) | Yes            | Left Front Thigh, Right Front Thigh     |
| Side Leg (Thigh)  | Yes            | Left Side Thigh, Right Side Thigh       |
| Back of Arm       | Yes            | Left Back Arm, Right Back Arm           |
| Buttocks          | Yes            | Left Buttock, Right Buttock             |

#### 3.2.3 Custom Locations

Users can add custom zones beyond the defaults (e.g., "Lower Back", "Hip"). Custom zones support the same laterality toggle. Users can also rename default zones. Deleting a zone that has historical data should soft-delete it (mark as disabled, retain history).

### 3.3 Site History

The app maintains a complete, chronological log of all site changes.

#### 3.3.1 History Entry Data Model

| Field         | Type    | Required | Description                                         |
|---------------|---------|----------|-----------------------------------------------------|
| id            | UUID    | Yes      | Unique identifier                                   |
| locationId    | UUID    | Yes      | Reference to the location used                      |
| startTime     | Date    | Yes      | When the site was applied (auto-set on log)         |
| endTime       | Date?   | No       | When the site was removed (auto-set on next change) |
| durationHours | Double? | No       | Computed: endTime - startTime in hours              |
| note          | String? | No       | Optional user note about the site                   |

#### 3.3.2 History View

The history view displays entries in reverse chronological order. Each entry shows the location name, start date/time, duration (if completed), and any notes. Users should be able to filter by location and by date range. Users can edit or delete history entries to correct mistakes. Editing should allow changing the location, timestamps, and notes.

### 3.4 Statistical Analysis

The statistics screen provides insights into site usage patterns and potential absorption issues.

#### 3.4.1 Per-Location Statistics

For each configured location, display:

- **Total uses:** Number of times this location has been used.
- **Average duration (hours):** Mean time a site remains active at this location. Helps identify locations where sites fail early or where the user tends to change sooner (possibly due to discomfort or poor absorption).
- **Median duration (hours):** Less sensitive to outliers than the mean.
- **Min/Max duration:** Range of usage durations.
- **Last used:** Date of most recent use.
- **Days since last use:** How long this location has been resting.

#### 3.4.2 Absorption Insight

The app should highlight locations where the average duration is notably shorter than the user's overall average. The logic is: if a user consistently removes a site early from a specific location, it may indicate discomfort or poor absorption. The threshold for flagging is configurable (default: 20% below overall average). Flagged locations should display a visual indicator and a brief explanation (e.g., "Average duration at this site is 18% below your overall average. This may indicate absorption issues.").

#### 3.4.3 Usage Distribution

A visual summary (bar chart or similar) showing how frequently each location is used. This helps the user see at a glance if they are over-rotating through certain sites. An ideal distribution is roughly equal usage across all enabled locations.

#### 3.4.4 Rotation Timeline

A timeline or calendar view showing which location was used on which dates. This provides a visual representation of the user's rotation pattern over the past 30, 60, or 90 days.

-----

## 4. Data Architecture & Storage

### 4.1 Persistence Requirements

- **Local persistence:** All data must be stored locally on the device for offline access.
- **Cloud sync:** Data must sync via iCloud (CloudKit) so it transfers automatically when the user upgrades to a new iPhone or restores from backup.
- **No account required:** The app should not require any user account or login. iCloud sync happens transparently via the user's Apple ID.

### 4.2 Recommended Stack

- **SwiftData:** Primary persistence framework. SwiftData automatically integrates with CloudKit for iCloud sync when configured with a CloudKit container. This is the recommended approach for new iOS apps targeting iOS 17+.
- **CloudKit container:** A CloudKit container (e.g., `iCloud.com.yourname.sitecycle`) must be configured in the app's entitlements for sync to work.
- **Fallback -- Core Data + NSPersistentCloudKitContainer:** If targeting iOS 16 or earlier, use Core Data with NSPersistentCloudKitContainer for iCloud sync. The data model is the same.

### 4.3 Data Model Summary

Two primary entities:

- **Location:** id (UUID), zone (String), side (String?, enum: left/right/nil), isEnabled (Bool), isCustom (Bool), sortOrder (Int).
- **SiteChangeEntry:** id (UUID), locationId (UUID, relationship to Location), startTime (Date), endTime (Date?), note (String?).

Relationships: Location has a one-to-many relationship with SiteChangeEntry.

### 4.4 Data Migration

Use SwiftData's built-in schema versioning for model migrations. Plan for future schema changes by defining a VersionedSchema from the start.

-----

## 5. User Interface

### 5.1 Navigation Structure

The app uses a tab bar with three tabs:

1. **Home** -- Current site status, prominent "Log Site Change" button, and quick-view of the current site location and how long it has been active.
2. **History** -- Chronological log of all site changes with filtering and editing.
3. **Statistics** -- Analytics dashboard with per-location stats, charts, and absorption insights.

Settings are accessible via a gear icon in the navigation bar (from any tab) and include location configuration, absorption threshold settings, and data export.

### 5.2 Home Screen

The home screen should display the current active site (location name, start time, elapsed hours), a circular or linear progress indicator showing time since last change (with a configurable target duration, default 72 hours), and a large, prominent "Log Site Change" button. If no site is currently active (first launch), the screen should prompt the user to log their first site.

### 5.3 Site Selection Screen

Presented as a modal sheet when the user taps "Log Site Change." Layout has three sections:

- **Avoid (red/orange section):** Shows 3 most recently used locations with their last-used date. Each item has a warning indicator.
- **Recommended (green section):** Shows 3 least recently used locations with their last-used date (or "Never used"). Each item has a checkmark or thumbs-up indicator.
- **All Locations:** Alphabetically sorted, complete list. Each location shows last-used date. Locations appearing in Avoid or Recommended sections are tagged accordingly.

Tapping any location selects it. A confirmation dialog shows the selection and offers an optional note text field before saving.

### 5.4 Design Principles

- Use native iOS design patterns (SwiftUI components, SF Symbols).
- Support Dynamic Type for accessibility.
- Support Dark Mode.
- Keep the site change flow to 2 taps maximum (tap button -> tap location -> confirm).
- Use semantic colors for avoid/recommended indicators that work in both light and dark mode.

-----

## 6. Technical Requirements

### 6.1 Platform & Frameworks

| Requirement  | Value                               |
|--------------|-------------------------------------|
| Platform     | iOS 17.0+                           |
| Language     | Swift 5.9+                          |
| UI Framework | SwiftUI                             |
| Persistence  | SwiftData with CloudKit integration |
| Charts       | Swift Charts framework              |
| Architecture | MVVM (Model-View-ViewModel)         |
| Min iPhone   | iPhone SE (3rd gen) and later       |

### 6.2 iCloud Sync Behavior

- Sync should be automatic and require no user action beyond being signed into iCloud.
- The app must handle merge conflicts gracefully. Since entries are append-only (site changes are new records), conflicts should be rare. Use last-writer-wins for Location edits.
- The app should work fully offline. Changes sync when connectivity is restored.
- Display a subtle sync status indicator (e.g., a small cloud icon) so the user knows if data is synced.

### 6.3 Notifications (Optional, v1.1)

An optional future enhancement: configurable local notifications to remind the user to change their site after a set number of hours (default: 72). This is not required for v1.0 but the data model should not preclude it.

-----

## 7. Settings

- **Manage Locations:** Navigate to the location configuration screen to enable/disable zones, toggle laterality, add custom zones, and reorder locations.
- **Target Duration:** Set the target number of hours between site changes (default: 72). Used for the home screen progress indicator.
- **Absorption Alert Threshold:** Set the percentage below average duration that triggers an absorption flag in statistics (default: 20%).
- **Export Data:** Export full history as CSV for sharing with healthcare providers. Format: date, location, duration_hours, note.
- **About:** App version, privacy policy link, support contact.

-----

## 8. First-Launch Onboarding

1. Welcome screen explaining the app's purpose.
2. Location configuration: present the default zones and let the user toggle which ones they use. This is the most important setup step.
3. Prompt to log their first site immediately.
4. Done -- navigate to home screen.

Onboarding should be skippable and all settings should be changeable later.

-----

## 9. Recommended Project Structure

| Path                                   | Purpose                                           |
|----------------------------------------|---------------------------------------------------|
| `Models/Location.swift`               | SwiftData model for body locations                |
| `Models/SiteChangeEntry.swift`        | SwiftData model for site change history           |
| `ViewModels/HomeViewModel.swift`      | Logic for home screen, current site, elapsed time |
| `ViewModels/SiteChangeViewModel.swift`| Recommendation engine, site selection logic       |
| `ViewModels/HistoryViewModel.swift`   | History filtering, editing, deletion              |
| `ViewModels/StatisticsViewModel.swift`| Statistical calculations, absorption analysis     |
| `Views/HomeView.swift`                | Home tab UI                                       |
| `Views/SiteSelectionSheet.swift`      | Modal site selection with recommendations         |
| `Views/HistoryView.swift`             | History tab UI                                    |
| `Views/StatisticsView.swift`          | Statistics tab with charts                        |
| `Views/SettingsView.swift`            | Settings screen                                   |
| `Views/LocationConfigView.swift`      | Location management screen                        |
| `Views/OnboardingView.swift`          | First-launch onboarding flow                      |
| `Utilities/CSVExporter.swift`         | CSV export functionality                          |
| `Utilities/DefaultLocations.swift`    | Seed data for default body zones                  |

-----

## 10. Acceptance Criteria

The following criteria define a complete v1.0 implementation:

1. User can configure body locations (enable/disable zones, set laterality, add custom zones).
2. User can log a site change in <=2 taps from the home screen.
3. Site selection screen displays the 3 most recent locations as "Avoid" and the 3 least recent as "Recommended."
4. All configured locations are available for selection regardless of recommendation status.
5. Logging a new site automatically closes the previous site's session with an end time.
6. Full history is viewable, filterable by location and date, and editable.
7. Statistics show per-location average/median/min/max duration, total uses, and days since last use.
8. Absorption insight flags locations with average duration below the configurable threshold.
9. Usage distribution chart is displayed.
10. Data persists locally via SwiftData and syncs across devices via iCloud/CloudKit.
11. App works fully offline.
12. Data can be exported as CSV.
13. App supports Dark Mode and Dynamic Type.
14. First-launch onboarding guides user through location setup.

-----

## 11. Out of Scope (v1.0)

- Integration with insulin pump hardware or CGM data.
- Blood glucose tracking or insulin dosing.
- Push notifications / reminders (planned for v1.1).
- iPad or macOS support (iPhone only for v1.0).
- Apple Watch companion app.
- Multi-user or family sharing.
- Body diagram / visual body map for site selection (potential v2.0 feature).

-----

*-- End of Specification --*
