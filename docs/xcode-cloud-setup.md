# Xcode Cloud Setup

This documents how to configure SiteCycle's Xcode Cloud workflows. Workflow creation happens in Xcode / App Store Connect, not in this repo, so this doc is the source of truth for how each one is configured — treat it the way [`testflight-setup.md`](testflight-setup.md) documents GitHub Actions signing.

Rollout is phased, each running in parallel with its GitHub Actions equivalent until parity is confirmed, then the GitHub Actions version is removed in a follow-up PR:

| Phase | Workflow | Mirrors | Status |
|---|---|---|---|
| 1 | Unit Tests | `ci.yml` build-and-test job | Trialing |
| 2 | UI Tests | `ui-tests.yml` | Trialing |
| 2 | Watch Build | `ci.yml` build-watch job | Trialing |
| 3 | TestFlight | `testflight.yml` | Trialing, manual-trigger only |
| 3 | Archive Check | `ci.yml` archive job | Trialing |

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
3. Xcode Cloud will offer to auto-create default workflows (typically a Build workflow and an Archive-on-release-branch workflow). **Decline these** and create the workflows below instead, one at a time.

## Phase 1 — Workflow: "Unit Tests"

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Xcode 26.x (closest available managed image — this project reports `objectVersion 60` / `LastUpgradeCheck 2600`), latest iOS Simulator runtime |
| Start Condition | Pull Request changes → target branch `main` |
| Action | Test only |
| Test Plan | `SiteCycleUnitTests` (repo root — contains only the `SiteCycleTests` target) |
| Destination | iPhone 16 Simulator (or Xcode Cloud's "any iOS Simulator" device-matrix default) |
| Post-actions | None |

This workflow is confirmed working (see PR [#75](https://github.com/ssabo/SiteCycle/pull/75)).

## Phase 2 — Workflow: "UI Tests"

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Same as Unit Tests |
| Start Condition | Pull Request changes → target branch `main`, filtered to changes under `SiteCycle/`, `SiteCycleUITests/`, `SiteCycle.xcodeproj/`, `SiteCycleConfig.xcconfig` — mirrors `ui-tests.yml`'s path filter so docs-only PRs don't consume Xcode Cloud compute minutes |
| Action | Test only |
| Test Plan | `SiteCycleUITests` (repo root — contains only the `SiteCycleUITests` target) |
| Destination | iPhone 16 Simulator |
| Post-actions | None |

The onboarding crash bug that originally blocked this (see `docs/ui-testing-roadmap.md`) only affects a happy-path test that was removed and never re-added — the current 15 UI tests across 6 files run reliably today in `ui-tests.yml`, so there's no known blocker here.

`ui-tests.yml` disables parallel testing (`-parallel-testing-enabled NO`, `-disable-concurrent-destination-testing`) to work around a GitHub Actions/macos-15-specific simulator-clone cleanup flake. Xcode Cloud provisions simulators differently, so this flake may simply not reproduce — leave parallel testing at its default during the trial and only disable it if the same failure mode shows up.

## Phase 2 — Workflow: "Watch Build"

| Setting | Value |
|---|---|
| Scheme | `SiteCycleWatch` |
| Environment | Same as above, watchOS Simulator |
| Start Condition | Pull Request changes → target branch `main` (no path filter — any app change can affect the watch target) |
| Action | Build only (no Test action — the watch scheme's Test action is empty; there's no test target for the watch app) |
| Post-actions | None |

## Phase 3 — Workflow: "TestFlight"

This is the workflow that actually removes the manual certificate/provisioning-profile dance in `testflight-setup.md`. `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM = G58SM6WLX7` are already set project-wide, which is exactly what Xcode Cloud needs — no `ExportOptions.plist`, no certs, no profiles, no API key file.

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Same as above |
| Start Condition | **None — manual trigger only** (see below). No automatic schedule configured for now. |
| Action | Archive (Release configuration) |
| Post-actions | None — a plain Archive already matches `testflight.yml`'s current behavior (upload only; distributing to a tester group is still done manually in App Store Connect) |

### Before the first Archive: fix the build number

Read this before triggering either the TestFlight or Archive Check workflow for the first time.

Xcode Cloud assigns **CFBundleVersion (build number)** as a single incrementing integer counter scoped to the whole app in Xcode Cloud — not per-branch or per-workflow. It starts at `1` for the first Xcode Cloud build ever, then `2`, `3`, ... for every subsequent Xcode Cloud build regardless of which workflow triggered it. It does **not** touch `MARKETING_VERSION` (currently hardcoded `1.0` in `project.pbxproj`) — that stays exactly as manual as it is today.

`testflight.yml` has already been uploading real builds using `github.run_number` as the build number (via `agvtool new-version -all`). If Xcode Cloud's counter starts at `1` and a build number ≥ 1 already exists in App Store Connect for version `1.0`, the first Xcode Cloud archive will be rejected as a duplicate/lower build number.

**Fix once, before the first Xcode Cloud archive:**
1. Check the highest existing build number for version `1.0` under App Store Connect → SiteCycle → TestFlight → Builds.
2. Go to App Store Connect → SiteCycle → **Xcode Cloud tab → Settings → Build Number tab → Edit "Next Build Number"**, and set it to that value + 1. Requires Admin or App Manager role.

After that, every future Xcode Cloud archive (from either workflow below) increments automatically — no more `agvtool`, no more `github.run_number`.

**Heads up if both Phase 3 workflows are active**: every successful Archive action — including the Archive Check workflow below, which has no distribution post-action — still gets delivered to App Store Connect's TestFlight → Builds list and consumes a number from that same shared counter. PR archive checks and real TestFlight release builds will interleave in one non-contiguous sequence, and the Builds list accumulates an entry per PR (never distributed to testers). This is harmless — Apple only requires monotonically increasing numbers — and TestFlight builds auto-expire after 90 days, but it's worth knowing going in.

### Triggering it

There's no automatic schedule, so trigger it manually (this replaces `workflow_dispatch`):
1. **In Xcode**: Report Navigator (`⌘9`) → **Cloud** tab → right-click the "TestFlight" workflow → **Start Build** → pick the branch (`main`) → **Start Build**.
2. **In App Store Connect** (no Xcode required): SiteCycle app → **Xcode Cloud** tab → select the workflow → **Start Build**.

## Phase 3 — Workflow: "Archive Check"

PR-time signing/export verification, mirrors `ci.yml`'s `archive` job.

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Same as above |
| Start Condition | Pull Request changes → target branch `main` |
| Action | Archive (Release configuration) |
| Post-actions | None |

Unlike `ci.yml`'s version, there's no need to skip fork PRs for secret-exposure reasons — Xcode Cloud's Automatic signing never exposes any credentials to the build environment, so there's nothing for a fork PR to exfiltrate. See the build-number/TestFlight-clutter note above before enabling this alongside the TestFlight workflow.

## Validating parity

Run the same tests locally against each new plan to confirm scope, e.g.:

```bash
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj \
  -testPlan SiteCycleUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(swap `-testPlan SiteCycleUITests` to check the UI-tests scope instead)

On a handful of trial PRs, confirm:
- Each Xcode Cloud check appears alongside its GitHub Actions equivalent.
- Pass/fail results match.
- Duration and reliability are comparable.

For the TestFlight/Archive Check workflows, manually trigger each once and confirm the resulting build appears in App Store Connect with the expected (corrected) build number, with no collision against prior `testflight.yml` uploads.

Once each pair holds parity, removing the corresponding GitHub Actions job is a separate follow-up PR.

## Do not do yet

- Don't add any Xcode Cloud check to required status checks in branch protection until its trial period confirms parity.
- Don't add an automatic schedule to the TestFlight workflow yet — manual-trigger only, deliberately, until it's been compared against `testflight.yml` at least once.
- Don't remove `testflight-setup.md`'s GitHub Secrets or the GitHub Actions workflows they support — that's the final step, after every Xcode Cloud workflow above has been trialed and cut over.
