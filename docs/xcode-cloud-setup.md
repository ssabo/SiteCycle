# Xcode Cloud Setup — Phase 1: Unit Tests

This documents how to configure the first Xcode Cloud workflow for SiteCycle: a unit-test-only workflow that runs `SiteCycleTests` on pull requests to `main`, in parallel with the existing `ci.yml` GitHub Actions job. Workflow creation happens in Xcode / App Store Connect, not in this repo, so this doc is the source of truth for how it's configured — treat it the way [`testflight-setup.md`](testflight-setup.md) documents GitHub Actions signing.

Unlike the GitHub Actions archive job, this workflow needs **no certificates, provisioning profiles, or secrets** — Xcode Cloud test actions run on simulator, and Xcode Cloud itself talks to App Store Connect directly for anything that does need signing (a later phase, see below).

## Prerequisites

- The signed-in Apple ID must have the **Admin**, **App Manager**, or **Account Holder** role on the SiteCycle team (`G58SM6WLX7`) in App Store Connect.
- The person connecting the repo needs **Admin** access on the `SiteCycle` GitHub repo (or be an org owner, if it moves into an org) to authorize the Xcode Cloud GitHub App.

## One-time: connect the repo

This flow starts in the Xcode app, hands off to a browser partway through for the GitHub authorization step, then comes back to Xcode:

1. In Xcode, open `SiteCycle.xcodeproj`, open the **Report Navigator** (`⌘9`), and click the **Cloud** tab in the left sidebar. Click **Create Workflow**.
   - The **Product > Xcode Cloud > Create Workflow** menu item does the same thing, but it isn't always present — it depends on Xcode version and whether an Apple Developer account with Xcode Cloud access is already signed in under Xcode > Settings > Accounts. The Report Navigator route is the reliable one; use the Product menu as a shortcut only if you see it.
2. Select the `SiteCycle` product and continue. When prompted to connect a source repository, click **Grant Access** — this opens **App Store Connect in your web browser**, not the Xcode app, for the actual GitHub authorization:
   - Link your Apple ID to GitHub and click **Authorize Xcode Cloud**.
   - Install the Xcode Cloud GitHub App on the repo (or your GitHub account/org) — a one-time OAuth-style consent, not a secret you manage.
   - GitHub redirects back to App Store Connect showing a green checkmark, then click **Continue in Xcode** to return to the Xcode app and finish setup there.
3. Xcode Cloud will offer to auto-create default workflows (typically a Build workflow and an Archive-on-release-branch workflow). **Decline these** and create the workflow below instead — we don't want an Archive workflow standing up before signing/TestFlight is deliberately migrated (see "Next steps").

## Workflow: "Unit Tests"

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Xcode 26.x (closest available managed image — this project reports `objectVersion 60` / `LastUpgradeCheck 2600`), latest iOS Simulator runtime |
| Start Condition | Pull Request changes → target branch `main` |
| Action | Test only |
| Test Plan | `SiteCycleUnitTests` (repo root — contains only the `SiteCycleTests` target, deliberately excludes `SiteCycleUITests`) |
| Destination | iPhone 16 Simulator (or Xcode Cloud's "any iOS Simulator" device-matrix default) |
| Post-actions | None yet |

The `SiteCycleUnitTests` test plan exists specifically so this workflow doesn't run `SiteCycleUITests` — CLAUDE.md documents a UI-test-only crash in `OnboardingView`'s paged `TabView` on Xcode 26 / iPhone 16 Pro sim, and running the full default test plan here on day one would produce a flaky/red check. The scheme's other, default test plan (`SiteCycle.xctestplan`) still includes both targets, matching the previous autocreated behavior for local Xcode runs.

Once connected, Xcode Cloud posts build/test results as a native GitHub check on the PR automatically — no extra webhook or notification config needed for that.

**Do not** add the Xcode Cloud check to required status checks in branch protection yet. That's a follow-up once the trial period below confirms parity with the existing GitHub Actions job.

## Validating parity

Run the same tests locally against the new plan to confirm scope:

```bash
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj \
  -testPlan SiteCycleUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

On a handful of trial PRs, confirm:
- The Xcode Cloud check appears alongside the existing `ci.yml` / `ui-tests.yml` checks.
- Pass/fail results match the GitHub Actions `build-and-test` job's `-only-testing:SiteCycleTests` result.
- Duration and reliability are comparable.

Once that holds, removing the GitHub Actions unit-test job (keeping lint + watch-build there) is a separate follow-up PR.

## Next steps (not part of this phase)

- Extend Xcode Cloud to `SiteCycleUITests` once the onboarding crash bug is fixed (see `docs/ui-testing-roadmap.md` "Step 6").
- Add a watch-build Xcode Cloud workflow (mirrors the `build-watch` GitHub Actions job).
- Migrate Archive/TestFlight to Xcode Cloud. This is the phase where Xcode Cloud's direct App Store Connect signing actually replaces the manual certificate/provisioning-profile export process in `testflight-setup.md` and retires the seven related GitHub Secrets — it's sequenced after unit tests prove the pipeline out, not before.
