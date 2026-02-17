# CI & TestFlight Deployment

This document covers the continuous integration and TestFlight deployment workflows for SiteCycle.

---

## CI Overview

The CI workflow (`.github/workflows/ci.yml`) runs automatically on every push to `main` and on pull requests targeting `main`. It performs two jobs:

1. **SwiftLint** — Installs SwiftLint via Homebrew and lints all Swift source files with `--strict` mode. Any warning is treated as an error.
2. **Build & Test** — Selects the latest Xcode 16 on a `macos-15` runner, detects an available iPhone simulator, builds the project with code signing disabled, and runs all unit tests.

Code signing is intentionally disabled in CI (`CODE_SIGN_IDENTITY=""`, `CODE_SIGNING_REQUIRED=NO`). The app's `ModelContainer` initialization includes a fallback from CloudKit (`.automatic`) to local-only (`.none`) so the app can launch without CloudKit entitlements in CI.

Concurrency is configured with `cancel-in-progress: true` so that new pushes to the same branch cancel any in-progress CI run.

---

## TestFlight Deployment Overview

The TestFlight workflow (`.github/workflows/testflight.yml`) archives the app, signs it with a distribution certificate, and uploads the IPA to App Store Connect for TestFlight distribution.

### Triggers

The workflow runs when:

- A **tag** matching `v*` is pushed (e.g., `v1.0.0`, `v1.0.1-beta`).
- A **manual dispatch** is triggered from the GitHub Actions UI (`workflow_dispatch`).

### What It Does

1. Checks out the code and selects Xcode 16.
2. Imports the Apple distribution certificate and provisioning profile into a temporary keychain.
3. Installs the App Store Connect API key for upload authentication.
4. Archives the app for iOS with manual code signing (`CODE_SIGN_STYLE=Manual`).
5. Exports the archive to an IPA using `ExportOptions.plist`.
6. Uploads the IPA to App Store Connect via `xcrun altool`.
7. Cleans up the temporary keychain, provisioning profile, and API key (runs even if prior steps fail).

---

## Required GitHub Secrets

All secrets must be configured in the repository settings before the TestFlight workflow can succeed.

| Secret Name | Description |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` Apple Distribution certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` certificate |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store distribution `.mobileprovision` file |
| `APPSTORE_CONNECT_API_KEY_ID` | The Key ID of your App Store Connect API key (e.g., `ABC1234DEF`) |
| `APPSTORE_CONNECT_API_ISSUER_ID` | The Issuer ID from App Store Connect (a UUID) |
| `APPSTORE_CONNECT_API_KEY_BASE64` | Base64-encoded `.p8` private key file from App Store Connect |

---

## Step-by-Step: Generating an App Store Connect API Key

The API key is used to authenticate the IPA upload to App Store Connect without requiring Apple ID credentials.

1. Open [App Store Connect](https://appstoreconnect.apple.com).
2. Navigate to **Users and Access** > **Integrations** > **App Store Connect API**.
3. Click the **+** button to create a new key.
4. Give it a name (e.g., "SiteCycle CI") and select the **Developer** role.
5. Click **Generate**.
6. **Download the `.p8` file immediately** — it can only be downloaded once.
7. Note the **Key ID** displayed next to your key name.
8. Note the **Issuer ID** shown at the top of the keys page.
9. Base64-encode the `.p8` file:
   ```bash
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
   ```
   This copies the base64 string to your clipboard.

You will need all three values: the Key ID, Issuer ID, and the base64-encoded `.p8` contents.

---

## Step-by-Step: Exporting the Distribution Certificate

The distribution certificate is used to sign the app for App Store / TestFlight distribution.

### If you already have a distribution certificate in Keychain Access:

1. Open **Keychain Access** on your Mac.
2. In the left sidebar, select **login** keychain and the **My Certificates** category.
3. Find the certificate named **"Apple Distribution: Your Name (TEAM_ID)"**.
4. Right-click the certificate and select **Export**.
5. Choose **Personal Information Exchange (.p12)** as the format.
6. Set a password when prompted — you will need this password as the `APPLE_CERTIFICATE_PASSWORD` secret.
7. Save the `.p12` file.
8. Base64-encode it:
   ```bash
   base64 -i Certificates.p12 | pbcopy
   ```

### If you need to create a new distribution certificate:

1. Open **Xcode** > **Settings** > **Accounts**.
2. Select your Apple Developer team and click **Manage Certificates**.
3. Click the **+** button and select **Apple Distribution**.
4. Xcode creates the certificate and installs it in your keychain.
5. Follow the export steps above to get the `.p12` file.

---

## Step-by-Step: Exporting the Provisioning Profile

The provisioning profile links your app's Bundle ID, distribution certificate, and team for App Store distribution.

1. Open the [Apple Developer Portal](https://developer.apple.com/account/resources/profiles/list).
2. Click the **+** button to create a new profile.
3. Select **App Store Connect** under the Distribution section and click **Continue**.
4. Select the App ID for `com.sitecycle.app` and click **Continue**.
5. Select your **Apple Distribution** certificate and click **Continue**.
6. Name the profile (e.g., "SiteCycle App Store Profile") and click **Generate**.
7. Download the `.mobileprovision` file.
8. Base64-encode it:
   ```bash
   base64 -i SiteCycle_App_Store_Profile.mobileprovision | pbcopy
   ```

**Note:** The profile name in the Apple Developer Portal must match the value in `ExportOptions.plist` under `provisioningProfiles`. The default in this repo is `"SiteCycle App Store Profile"`. Update `ExportOptions.plist` if you use a different name.

---

## Step-by-Step: Adding Secrets to GitHub

1. Navigate to your GitHub repository.
2. Go to **Settings** > **Secrets and variables** > **Actions**.
3. Click **New repository secret**.
4. Add each of the 6 secrets listed in the table above:
   - **Name:** Enter the exact secret name (e.g., `APPLE_CERTIFICATE_BASE64`).
   - **Value:** Paste the corresponding value (base64 string, password, key ID, etc.).
5. Click **Add secret** for each one.

Verify all 6 secrets are listed before triggering a release.

---

## Triggering a TestFlight Release

### Option 1: Tag Push (Recommended)

Create and push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow triggers automatically on any tag matching the `v*` pattern. Use [semantic versioning](https://semver.org) for tags:

- `v1.0.0` — initial release
- `v1.0.1` — patch/bug fix
- `v1.1.0` — minor feature addition
- `v2.0.0` — major version

### Option 2: Manual Dispatch

1. Go to your repository on GitHub.
2. Navigate to **Actions** > **TestFlight** workflow.
3. Click **Run workflow**.
4. Select the branch to build from and click **Run workflow**.

This is useful for testing the workflow without creating a tag.

---

## Troubleshooting

### "No signing certificate" error

Ensure `APPLE_CERTIFICATE_BASE64` and `APPLE_CERTIFICATE_PASSWORD` are correct. Verify the certificate hasn't expired in the Apple Developer Portal.

### "No provisioning profile" error

Ensure `APPLE_PROVISIONING_PROFILE_BASE64` is correct and the profile name matches `ExportOptions.plist`. Verify the profile hasn't expired and includes the correct certificate and Bundle ID.

### "Unable to authenticate" upload error

Verify `APPSTORE_CONNECT_API_KEY_ID`, `APPSTORE_CONNECT_API_ISSUER_ID`, and `APPSTORE_CONNECT_API_KEY_BASE64` are correct. Ensure the API key has the **Developer** (or **Admin**) role and hasn't been revoked.

### Build succeeds but upload fails

Ensure the app's Bundle ID (`com.sitecycle.app`) is registered in App Store Connect and that at least one version record exists. Go to App Store Connect > My Apps and create the app entry if it doesn't exist.
