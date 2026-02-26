# TestFlight CI Setup

This documents the provisioning profiles and GitHub secrets required for the CI archive job to build, sign, and export the app for TestFlight.

## App IDs

Three App IDs are registered in the Apple Developer portal:

| App ID | Bundle ID | Platform |
|--------|-----------|----------|
| SiteCycle | `com.sitecycle.app` | iOS |
| SiteCycle Watch App | `com.sitecycle.app.watchkitapp` | watchOS |
| SiteCycle Watch Widgets | `com.sitecycle.app.watchkitapp.widgets` | watchOS |

## Provisioning Profiles

Each target needs its own App Store distribution provisioning profile:

| Profile Name | Bundle ID | Type |
|-------------|-----------|------|
| SiteCycle App Store Profile | `com.sitecycle.app` | App Store |
| SiteCycle Watch App Store Profile | `com.sitecycle.app.watchkitapp` | App Store |
| SiteCycle Watch Widget App Store Profile | `com.sitecycle.app.watchkitapp.widgets` | App Store |

### Creating the Watch provisioning profiles

If the Watch App IDs and profiles don't exist yet, follow these steps:

#### 1. Register App IDs

Go to [Apple Developer > Identifiers](https://developer.apple.com/account/resources/identifiers/list):

**Watch App (`com.sitecycle.app.watchkitapp`):**
1. Click **+** to register a new identifier
2. Select **App IDs** > **App**
3. Description: "SiteCycle Watch App"
4. Bundle ID (Explicit): `com.sitecycle.app.watchkitapp`
5. Under Capabilities, enable:
   - **App Groups** (add `group.com.sitecycle.app`)
   - **CloudKit** (uses the existing `iCloud.com.sitecycle.app` container)
   - **Push Notifications**
6. Click **Continue** > **Register**

**Watch Widgets (`com.sitecycle.app.watchkitapp.widgets`):**
1. Click **+** to register a new identifier
2. Select **App IDs** > **App**
3. Description: "SiteCycle Watch Widgets"
4. Bundle ID (Explicit): `com.sitecycle.app.watchkitapp.widgets`
5. Under Capabilities, enable:
   - **App Groups** (add `group.com.sitecycle.app`)
   - **CloudKit** (uses the existing `iCloud.com.sitecycle.app` container)
6. Click **Continue** > **Register**

#### 2. Create App Group (if not already registered)

Go to [Apple Developer > Identifiers](https://developer.apple.com/account/resources/identifiers/list) and filter by **App Groups**:

1. If `group.com.sitecycle.app` doesn't exist, click **+**
2. Select **App Groups**
3. Description: "SiteCycle App Group"
4. Identifier: `group.com.sitecycle.app`
5. Click **Continue** > **Register**

#### 3. Create Provisioning Profiles

Go to [Apple Developer > Profiles](https://developer.apple.com/account/resources/profiles/list):

**Watch App profile:**
1. Click **+** to generate a new profile
2. Select **App Store Connect** (under Distribution)
3. Select App ID: `com.sitecycle.app.watchkitapp`
4. Select your **Apple Distribution** certificate (same one used for the iOS app)
5. Name: `SiteCycle Watch App Store Profile`
6. Click **Generate** > **Download**

**Watch Widgets profile:**
1. Click **+** to generate a new profile
2. Select **App Store Connect** (under Distribution)
3. Select App ID: `com.sitecycle.app.watchkitapp.widgets`
4. Select your **Apple Distribution** certificate (same one used for the iOS app)
5. Name: `SiteCycle Watch Widget App Store Profile`
6. Click **Generate** > **Download**

#### 4. Add GitHub Secrets

Base64-encode each downloaded `.mobileprovision` file and add as repository secrets:

```bash
# Watch App profile
base64 -i "SiteCycle_Watch_App_Store_Profile.mobileprovision" | pbcopy
# Paste as: APPLE_WATCH_PROVISIONING_PROFILE_BASE64

# Watch Widgets profile
base64 -i "SiteCycle_Watch_Widgets_App_Store_Profile.mobileprovision" | pbcopy
# Paste as: APPLE_WATCH_WIDGETS_PROVISIONING_PROFILE_BASE64
```

Go to **GitHub repo > Settings > Secrets and variables > Actions** and add:

| Secret Name | Value |
|-------------|-------|
| `APPLE_WATCH_PROVISIONING_PROFILE_BASE64` | Base64-encoded Watch App profile |
| `APPLE_WATCH_WIDGETS_PROVISIONING_PROFILE_BASE64` | Base64-encoded Watch Widgets profile |

## All Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `APPLE_CERTIFICATE_BASE64` | Apple Distribution certificate (.p12), base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the .p12 certificate |
| `APPLE_PROVISIONING_PROFILE_BASE64` | iOS App Store provisioning profile |
| `APPLE_WATCH_PROVISIONING_PROFILE_BASE64` | Watch App Store provisioning profile |
| `APPLE_WATCH_WIDGETS_PROVISIONING_PROFILE_BASE64` | Watch Widgets App Store provisioning profile |
| `APPSTORE_CONNECT_API_KEY_BASE64` | App Store Connect API key (.p8), base64-encoded |
| `APPSTORE_CONNECT_API_KEY_ID` | API key ID |

## How the Archive Works

The CI archive step (`ci.yml`) does the following:

1. Installs the distribution certificate into a temporary keychain
2. Installs all three provisioning profiles to `~/Library/MobileDevice/Provisioning Profiles/`
3. Runs `xcodebuild archive` with `CODE_SIGN_STYLE=Manual` and `CODE_SIGN_IDENTITY="Apple Distribution"`
4. Each target resolves its profile via the `PROVISIONING_PROFILE_SPECIFIER` in `ExportOptions.plist`
5. Exports the IPA using `ExportOptions.plist` which maps each bundle ID to its profile name

## ExportOptions.plist

The export options file maps bundle IDs to provisioning profile names:

```xml
<key>provisioningProfiles</key>
<dict>
    <key>com.sitecycle.app</key>
    <string>SiteCycle App Store Profile</string>
    <key>com.sitecycle.app.watchkitapp</key>
    <string>SiteCycle Watch App Store Profile</string>
    <key>com.sitecycle.app.watchkitapp.widgets</key>
    <string>SiteCycle Watch Widget App Store Profile</string>
</dict>
```
