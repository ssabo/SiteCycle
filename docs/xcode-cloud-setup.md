# Xcode Cloud Setup

This documents how to configure SiteCycle's Xcode Cloud workflows — the **active CI** for this repo. Workflow creation happens in Xcode / App Store Connect, not in this repo, so this doc is the source of truth for how each one is configured — treat it the way [`testflight-setup.md`](testflight-setup.md) documented GitHub Actions signing (now deprecated).

`ci.yml`, `ui-tests.yml`, and `testflight.yml` are **disabled** (`gh workflow disable` — kept in the repo, not removed, in case a rollback is ever needed). `stale-branch-cleanup.yml` is unrelated to build/test/publish and stays enabled. `lint.yml` (SwiftLint) also stays enabled permanently, by design — Xcode Cloud has no built-in lint step, so this is the one piece of CI that isn't migrating.

There are two Xcode Cloud workflows: **"CI"** (everything except distribution — unit tests, UI tests, watch build, and a signing-verification archive, as four parallel actions in one workflow) and **"TestFlight"** (archive + upload). They were originally set up as five separate workflows (one per action); see "Why one combined CI workflow" below for why that changed.

| Workflow | Replaces | Trigger |
|---|---|---|
| CI | `ci.yml` (build-and-test, build-watch, archive jobs), `ui-tests.yml` | Every PR to `main` |
| TestFlight | `testflight.yml` | Manual (any branch/PR) + automatic on `main` changes |

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
3. Xcode Cloud will offer to auto-create default workflows (typically a Build workflow and an Archive-on-release-branch workflow). **Decline these** and create the two workflows below instead.

## Workflow: "CI"

One workflow, four actions — Xcode Cloud only ever runs actions within a workflow in parallel (there's no sequential option), so all four run concurrently on every PR.

| Action | Scheme | Type | Test Plan / Config |
|---|---|---|---|
| Unit Tests | `SiteCycle` | Test | `SiteCycleUnitTests` (repo root — `SiteCycleTests` target only) |
| UI Tests | `SiteCycle` | Test | `SiteCycleUITests` (repo root — `SiteCycleUITests` target only) |
| Watch Build | `SiteCycleWatch` | Build | — (no test target exists for the watch app) |
| Archive Check | `SiteCycle` | Archive | Release configuration, no post-action (signing/export verification only, never distributed) |

- **Environment**: Xcode 26.x (closest available managed image — this project reports `objectVersion 60` / `LastUpgradeCheck 2600`), latest iOS/watchOS Simulator runtimes.
- **Start Condition**: Pull Request changes → target branch `main`. No path filter.
- **Post-actions**: None.

### Why one combined CI workflow

This was originally four separate workflows (Unit Tests, UI Tests, Watch Build, Archive Check), each with its own start condition — `ui-tests.yml`'s path filter (skip docs-only PRs) was mirrored onto the standalone UI Tests workflow, for instance. It's since been consolidated into one "CI" workflow with four parallel actions instead, deliberately:

- **Build numbers are a single counter shared across the whole app in Xcode Cloud**, not per-workflow (see "Build numbering" below). Four separate workflows all triggering on the same PR meant four separate builds consuming four slots in that shared counter per PR. One combined workflow with four actions is one build, consuming far fewer numbers over time.
- **Trade-off accepted**: UI Tests no longer has its own path filter, so it now runs on every PR instead of skipping docs-only changes. Worth it for the build-number savings.

### Known gaps carried over from the original per-workflow setup

- The onboarding crash bug that once blocked UI tests (see `docs/ui-testing-roadmap.md`) only affects a happy-path test that was removed and never re-added — the current 15 UI tests across 6 files run reliably, so this isn't a live blocker.
- `ui-tests.yml` disabled parallel testing (`-parallel-testing-enabled NO`, `-disable-concurrent-destination-testing`) to work around a GitHub Actions/macos-15-specific simulator-clone cleanup flake. Xcode Cloud provisions simulators differently, so this flake may simply not reproduce — leave parallel testing at its default and only disable it if the same failure mode shows up.
- Unlike `ci.yml`'s archive job, there's no need to skip fork PRs for secret-exposure reasons on the Archive Check action — Xcode Cloud's Automatic signing never exposes credentials to the build environment.

## Workflow: "TestFlight"

This is the workflow that actually removes the manual certificate/provisioning-profile dance in `testflight-setup.md`. `CODE_SIGN_STYLE = Automatic` and `DEVELOPMENT_TEAM = G58SM6WLX7` are already set project-wide, which is exactly what Xcode Cloud needs — no `ExportOptions.plist`, no certs, no profiles, no API key file.

| Setting | Value |
|---|---|
| Scheme | `SiteCycle` |
| Environment | Same as CI |
| Action | Archive (Release configuration) |
| Post-actions | None — a plain Archive already matches `testflight.yml`'s current behavior (upload only; distributing to a tester group is still done manually in App Store Connect) |

**Start conditions (both configured):**
1. **Manual** — startable on demand against any branch or PR (see "Triggering it manually" below).
2. **Automatic** — Branch Changes on `main`. Every merge to `main` triggers an archive + upload automatically, replacing `testflight.yml`'s monthly cron with continuous delivery to TestFlight on every merge.

### Triggering it manually

For ad-hoc builds off any branch or open PR, not just `main`:
1. **In Xcode**: Report Navigator (`⌘9`) → **Cloud** tab → right-click the "TestFlight" workflow → **Start Build** → pick the branch/PR → **Start Build**.
2. **In App Store Connect** (no Xcode required): SiteCycle app → **Xcode Cloud** tab → select the workflow → **Start Build**.

## Build numbering

Read this before triggering the first Xcode Cloud archive if you haven't already.

Xcode Cloud assigns **CFBundleVersion (build number)** as a single incrementing integer counter scoped to the whole app in Xcode Cloud — not per-branch or per-workflow. It starts at `1` for the first Xcode Cloud build ever, then `2`, `3`, ... for every subsequent Xcode Cloud build regardless of which workflow or action triggered it (this is why consolidating into one "CI" workflow matters — see above). It does **not** touch `MARKETING_VERSION` (currently hardcoded `1.0` in `project.pbxproj`) — that stays exactly as manual as it is today.

`testflight.yml` has already been uploading real builds using `github.run_number` as the build number (via `agvtool new-version -all`). If Xcode Cloud's counter starts at `1` and a build number ≥ 1 already exists in App Store Connect for version `1.0`, the first Xcode Cloud archive will be rejected as a duplicate/lower build number.

**Fix once, before the first Xcode Cloud archive:**
1. Check the highest existing build number for version `1.0` under App Store Connect → SiteCycle → TestFlight → Builds.
2. Go to App Store Connect → SiteCycle → **Xcode Cloud tab → Settings → Build Number tab → Edit "Next Build Number"**, and set it to that value + 1. Requires Admin or App Manager role.

After that, every future Xcode Cloud archive (from either the CI workflow's Archive Check action or the TestFlight workflow) increments automatically — no more `agvtool`, no more `github.run_number`.

**Heads up**: the CI workflow's Archive Check action still delivers to App Store Connect's TestFlight → Builds list on every PR (even with no distribution post-action) and consumes a number from the same shared counter as real TestFlight releases. PR archive checks and release builds interleave in one non-contiguous sequence, and the Builds list accumulates a never-distributed entry per PR. Harmless — Apple only requires monotonically increasing numbers — and TestFlight builds auto-expire after 90 days, but worth knowing.

## Validating parity

Run the same tests locally against each test plan to confirm scope, e.g.:

```bash
xcodebuild test -scheme SiteCycle -project SiteCycle.xcodeproj \
  -testPlan SiteCycleUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

(swap `-testPlan SiteCycleUITests` to check the UI-tests scope instead)

Parity is confirmed and `ci.yml`, `ui-tests.yml`, and `testflight.yml` are disabled (not removed — see the note at the top of this doc and `CLAUDE.md`'s "CI / CD" section).

## Not done yet

- No Xcode Cloud check is marked as a required status check in branch protection (`main` currently has none configured either way).
- `testflight-setup.md`'s GitHub Secrets haven't been removed, and the disabled GitHub Actions workflow files are still in the repo — full removal (secrets + files) is a separate, not-yet-requested step. Disabling is reversible via `gh workflow enable <name>` if anything needs to roll back.
