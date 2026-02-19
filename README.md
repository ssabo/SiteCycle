# SiteCycle

An iOS app for insulin pump users to track and manage infusion site rotation. SiteCycle recommends optimal pump site placement based on your usage history to help prevent lipohypertrophy, scarring, and absorption issues.

## Features

- **Smart Site Recommendations** - Suggests the best locations for your next infusion site based on recovery time, and warns you about recently-used sites to avoid
- **Site Change Logging** - Log each site change with a single tap; the app automatically timestamps entries and closes the previous session
- **Location Configuration** - 14 default body locations (7 zones with left/right sides), plus support for custom zones
- **History** - Full chronological log with filtering by location and date range, plus editing and deletion
- **Statistics & Charts** - Per-location usage counts, average/median/min/max durations, absorption insights, and usage distribution charts
- **CSV Export & Import** - Export your complete history as CSV for backup or analysis, and import from CSV
- **iCloud Sync** - Seamless CloudKit sync across devices with no account required
- **Onboarding** - Guided setup to configure your preferred infusion sites

## Screenshots

<table>
  <tr>
    <td align="center"><strong>Home</strong></td>
    <td align="center"><strong>Log Site Change</strong></td>
    <td align="center"><strong>History</strong></td>
  </tr>
  <tr>
    <td><img src="images/home-active-site.png" width="200" alt="Home screen showing active site and progress ring"></td>
    <td><img src="images/log-site-change-recommendations.png" width="200" alt="Site selection sheet with recommended locations"></td>
    <td><img src="images/history-view.png" width="200" alt="History view with filterable site change log"></td>
  </tr>
  <tr>
    <td align="center"><strong>Statistics</strong></td>
    <td align="center"><strong>Settings</strong></td>
    <td align="center"><strong>Manage Locations</strong></td>
  </tr>
  <tr>
    <td><img src="images/statistics-view.png" width="200" alt="Statistics view with per-location usage data"></td>
    <td><img src="images/settings-view.png" width="200" alt="Settings screen with preferences and CSV export"></td>
    <td><img src="images/manage-locations-view.png" width="200" alt="Location management with zone toggles"></td>
  </tr>
</table>

## Requirements

- iOS 26.0+
- Xcode 26
- Swift 6.0

## Tech Stack

- **SwiftUI** for the interface
- **SwiftData** with CloudKit for persistence and sync
- **Swift Charts** for statistics visualizations
- **MVVM architecture** (Models, ViewModels, Views, Utilities)
- **Zero external dependencies** - built entirely with Apple frameworks

## Building

```bash
# Build for iOS Simulator
xcodebuild build \
  -scheme SiteCycle \
  -project SiteCycle.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test \
  -scheme SiteCycle \
  -project SiteCycle.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project Structure

```
SiteCycle/
  Models/
    Location.swift              # Body location model (zone, side, enabled state)
    SiteChangeEntry.swift       # Site change event (start/end time, notes)
  ViewModels/
    HomeViewModel.swift         # Active site status, elapsed time, progress
    SiteChangeViewModel.swift   # Recommendation engine, site logging
    HistoryViewModel.swift      # History queries, filtering, editing
    StatisticsViewModel.swift   # Usage stats, absorption insights
  Views/
    HomeView.swift              # Dashboard with active site and progress ring
    SiteSelectionSheet.swift    # Site picker with avoid/recommended sections
    HistoryView.swift           # Filterable history log
    StatisticsView.swift        # Charts and per-location stats
    LocationConfigView.swift    # Add/edit/reorder body locations
    SettingsView.swift          # Target duration, export, preferences
    OnboardingView.swift        # First-launch setup flow
  Utilities/
    DefaultLocations.swift      # Seeds 14 default locations on first launch
    CSVExporter.swift           # RFC 4180-compliant CSV export
    CSVImporter.swift           # CSV import with validation
SiteCycleTests/                 # Swift Testing suite
```

## How It Works

When you change your infusion site, open SiteCycle and tap "Log Site Change." The app shows your locations sorted into three sections:

1. **Recommended** (green) - The 3 least recently used locations with the most recovery time
2. **All Locations** - Every configured location with inline badges: orange warnings for recently-used sites to avoid, green checkmarks for recommended sites

Select a location, optionally add a note, and confirm. The app handles the rest: timestamping, closing the previous session, and updating recommendations for next time.

## CI/CD

GitHub Actions workflows handle continuous integration and deployment:

- **CI** (`ci.yml`) - Runs SwiftLint and builds/tests on every push and PR to `main`
- **TestFlight** (`testflight.yml`) - Automated TestFlight builds for beta distribution

See [CI.md](CI.md) for setup details.

## License

All rights reserved.
