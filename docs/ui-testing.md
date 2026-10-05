# UI Testing

SiteCycle keeps **one** XCUITest smoke test (`SiteCycleUITests/SmokeTests.swift`).
This replaces an earlier plan (`docs/ui-testing-roadmap.md`, removed) to grow a
broad XCUITest suite screen by screen. This doc records why we cut it, so the
suite doesn't grow back without a reason.

## What the smoke test covers

`testLogSiteChangesEndToEnd`: launch → log two site changes via Home → All
Locations → confirm → Home shows the new active site → History shows two rows
with exactly one Active badge.

That's the wiring unit tests can't see: sheets present, confirm saves through
the ViewModel, and `@Query`-backed views refresh from SwiftData. A launch crash
is already caught by the unit tests, since `SiteCycleTests` is hosted by the app.

## Why the broader suite was removed

Reviewed in October 2026, after 15 tests across 6 files had shipped (PRs #67–69):

- **It mostly duplicated unit tests.** Closing the previous entry, soft vs.
  hard delete, the last-enabled-location guard, and settings persistence are
  ViewModel or `@AppStorage` behavior that `SiteCycleTests/` already covers
  faster and more reliably.
- **It didn't cover where bugs actually happened.** Past fix PRs were almost
  all in the Watch app, CloudKit sync (disabled under `-uiTestMode`), or sort
  and recommendation logic (unit-test territory). None would have been caught
  by the iOS XCUITest suite.
- **Some assertions were weaker than the test names.** The "second site closes
  previous entry" test passed even when both entries stayed active, and the
  "start time updates duration" test never touched the start time.
- **It was fragile.** Coordinate taps on toggles, backspace loops to clear text
  fields, `Thread.sleep`, plus two planned tests dropped because
  `confirmationDialog` Cancel and in-Form `DatePicker`s can't be driven
  reliably. Each Xcode/SwiftUI upgrade risks red CI with no app regression.
- **It cost CI time on every PR**, docs-only PRs included, against Xcode
  Cloud's monthly compute-hour budget.
- **It shipped test scaffolding in the app.** A fixture loader and two JSON
  fixtures were compiled into the app target. Both are gone.

## How to guard against UI regressions instead

1. **Keep logic out of Views.** If a View makes a decision (badge choice, empty
   state, a guard), move it into a ViewModel and unit-test it there.
2. **Use `#Preview`s** for layout and visual checks.
3. **Install the TestFlight build.** Every merge to `main` uploads one.
4. **Extend the smoke test only for a real wiring regression** that unit
   tests couldn't have caught, and prefer adding an assertion to the
   existing flow over adding a new test.

## Where it runs

The UI test plan (`SiteCycleUITests.xctestplan`) runs as a Test action in the
Xcode Cloud **"TestFlight"** workflow (on merges to `main`), not on every PR.
See [`xcode-cloud-setup.md`](xcode-cloud-setup.md).

## Known app bug (not a testing task)

The Welcome → Configure transition in `OnboardingView`'s paged `TabView` has
been seen to terminate the app during UI-test runs (Xcode 26 / iPhone 16 Pro
simulator). It was found while writing UI tests and still needs a fix as an
app bug. Diagnose it on a Mac using the crash log from the xcresult bundle.
