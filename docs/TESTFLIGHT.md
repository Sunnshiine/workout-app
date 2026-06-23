# TestFlight Deployment

This repo can archive and upload `WorkoutTracker` to App Store Connect with:

```bash
MARKETING_VERSION=1.0 BUILD_NUMBER=$(date -u +%Y%m%d%H%M) scripts/upload-testflight.sh
```

The script archives the Release build, signs it with team `K74Q6RKFBY`, and uploads it with `Config/TestFlightExportOptions.plist`.

## One-Time Setup

1. Enroll the Apple ID in the Apple Developer Program and make sure Xcode can use team `K74Q6RKFBY`.
2. In Certificates, Identifiers & Profiles, make sure these bundle IDs exist or let `xcodebuild -allowProvisioningUpdates` create them:
   - `com.sunnypatel.WorkoutTracker`
   - `com.sunnypatel.WorkoutTracker.Widgets`
3. In App Store Connect, create the app record for bundle ID `com.sunnypatel.WorkoutTracker`.
4. Create a Google OAuth iOS client for `com.sunnypatel.WorkoutTracker`, then fill in `Secrets.xcconfig` from `Secrets.xcconfig.template`.

## Credentials

The script defaults to Xcode's signed-in account. For App Store Connect API-key auth, set all three variables:

```bash
APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/AuthKey_XXXXXXXXXX.p8 \
APP_STORE_CONNECT_KEY_ID=XXXXXXXXXX \
APP_STORE_CONNECT_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
scripts/upload-testflight.sh
```

Do not commit `.p8` files or `Secrets.xcconfig`.

## Distribution Scope

`Config/TestFlightExportOptions.plist` sets `testFlightInternalTestingOnly` to `true` so early uploads are limited to internal TestFlight. Set it to `false` before uploading a build intended for external TestFlight or App Store release.

After upload processing finishes in App Store Connect, add the build to an internal testing group under TestFlight.
