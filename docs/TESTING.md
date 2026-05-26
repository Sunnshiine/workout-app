# Manual Testing on the iOS Simulator

## Prerequisites

- **Xcode 26.3** — required for the iOS 26.0 deployment target
- **iOS 26.3.1 simulator runtime** — should already be installed; check via
  Xcode → Settings → Platforms if the app fails to launch

## Running the App

1. Open `WorkoutTracker.xcodeproj` in Xcode
2. Select the **WorkoutTracker** scheme (top bar, left of the device picker)
3. Choose a simulator — **iPhone 17 Pro** is a good default

   > Available devices: iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max, iPhone Air, iPhone 16e.
   > "iPhone 16" does not exist in the iOS 26.3.1 runtime — don't use it.

4. Press **Cmd+R** to build and run

Build time is ~30–60 s on first run (Swift packages resolve). Subsequent builds are fast.

## First-Run Onboarding

The app opens to **OnboardingView** on a fresh install (no sign-in, no sheet configured):

1. **Sign in with Google** — tap the button; a Safari sheet opens for OAuth. Use your Google account that has read access to the training sheet.
2. Once signed in, a text field appears — **paste the full Google Sheet URL** (e.g. `https://docs.google.com/spreadsheets/d/<ID>/edit`).
3. Tap **Save**. The app validates the URL and extracts the sheet ID. A bad URL shows an inline error.
4. On success the app navigates to **SessionView**.

## What This Branch Has (plan-1/read-only-viewer)

- Onboarding flow (sign in + sheet URL)
- `SyncCoordinator` — fetches the sheet from the Sheets REST API, parses it, and persists the Block to SwiftData
- `WorkoutStore` — loads the Block and derives the current Session
- `SessionView` — displays the current Session read-only (exercises and sets, no logging yet)

## Resetting State

To start fresh (re-trigger onboarding):

- **Delete the app** from the simulator home screen → reinstall via Cmd+R

Or from the Xcode menu: **Product → Scheme → Edit Scheme → Arguments** and add a launch argument to clear defaults on boot — or just delete and reinstall, it's faster.

## Running via xcodebuild (no Xcode GUI)

```bash
xcodebuild -project WorkoutTracker.xcodeproj \
  -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

To boot and install without Xcode:

```bash
# Boot the simulator
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# Build + install
xcodebuild -project WorkoutTracker.xcodeproj \
  -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build

# The .app path is in DerivedData — easier to just use Cmd+R in Xcode
```
