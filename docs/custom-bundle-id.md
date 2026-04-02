# Building SiteCycle with a Custom Bundle ID

The bundle IDs in this project (`com.sitecycle.app`, etc.) are registered to the original developer's Apple account. Anyone building from source for a real device needs their own unique prefix — the same pattern used by the Loop app.

## How it works

`SiteCycleConfig.xcconfig` defines a build variable `SITECYCLE_BUNDLE_PREFIX` (default: `com.sitecycle`). All bundle IDs, the iCloud container, and the app group are derived from that single variable:

| Identifier | Value |
|------------|-------|
| iOS app | `$(SITECYCLE_BUNDLE_PREFIX).app` |
| Watch app | `$(SITECYCLE_BUNDLE_PREFIX).app.watchkitapp` |
| Widget extension | `$(SITECYCLE_BUNDLE_PREFIX).app.watchkitapp.widgets` |
| iCloud container | `iCloud.$(SITECYCLE_BUNDLE_PREFIX).app` |
| App group | `group.$(SITECYCLE_BUNDLE_PREFIX).app` |

You override the prefix in a local file that is gitignored, so your personal setting never enters version control.

## Step-by-step setup

### 1. Create your override file

```bash
cp SiteCycleConfigOverride.xcconfig.template SiteCycleConfigOverride.xcconfig
```

Open `SiteCycleConfigOverride.xcconfig` and change the prefix to something unique to you:

```
SITECYCLE_BUNDLE_PREFIX = com.johndoe.sitecycle
```

Use a reverse-DNS string based on a domain or identifier you own (or just your Apple Developer email username) with `.sitecycle` appended. It only needs to be globally unique within Apple's system.

### 2. Register App IDs in the Apple Developer portal

Go to [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → Identifiers.

Register these three App IDs (replacing `com.johndoe.sitecycle` with your prefix):

| Name | Bundle ID | Capabilities |
|------|-----------|--------------|
| SiteCycle | `com.johndoe.sitecycle.app` | CloudKit, Push Notifications |
| SiteCycle Watch App | `com.johndoe.sitecycle.app.watchkitapp` | App Groups |
| SiteCycle Watch Widgets | `com.johndoe.sitecycle.app.watchkitapp.widgets` | App Groups |

### 3. Create the iCloud container

In Identifiers → Containers, create:

```
iCloud.com.johndoe.sitecycle.app
```

Then go back to the iOS App ID (`com.johndoe.sitecycle.app`) → Edit → CloudKit and associate the container you just created.

### 4. Create the app group

In Identifiers → App Groups, create:

```
group.com.johndoe.sitecycle.app
```

Associate this app group with the Watch app App ID and the Watch Widgets App ID.

> The iOS app uses WatchConnectivity (not the app group directly for reads), but PhoneConnectivityManager also writes state to the app group so the widget can read it. If you want the watch complications to work, also add the app group to the iOS App ID.

### 5. Set your team in Xcode

Open the project in Xcode. For each of the three targets (SiteCycle, SiteCycleWatch, SiteCycleWatchWidgets):

- Signing & Capabilities → Team → select your team
- Leave "Automatically manage signing" enabled

Xcode will generate provisioning profiles automatically once the App IDs exist.

### 6. Build and run

Select your device and hit Run. The bundle IDs will match your Apple Developer account and signing will succeed.

## Troubleshooting

**"An iCloud Container with identifier ... is not available"**
The iCloud container hasn't been created in the portal yet, or it hasn't been associated with your App ID. Repeat step 3.

**"No profiles for ... were found"**
The App ID doesn't exist yet in the portal. Repeat step 2.

**Build variable not applied / bundle ID is empty**
Make sure `SiteCycleConfigOverride.xcconfig` (not just the `.template`) exists at the project root next to `SiteCycleConfig.xcconfig`.
