# Manual Testing on the iOS Simulator

Part of [docs/TESTING.md](../TESTING.md).

## Prerequisites

- **Xcode 27** with the **iOS 27.0 simulator runtime**, the runtime CI and the Visual Baselines use.
  Check Xcode → Settings → Platforms if the app fails to launch.

## Running the App

1. Open `WorkoutTracker.xcodeproj` in Xcode
2. Select the **WorkoutTracker** scheme (top bar, left of the device picker)
3. Choose a simulator — **iPhone 17 Pro** on iOS 27.0 is a good default

4. Press **Cmd+R** to build and run

Build time is ~30–60 s on first run (Swift packages resolve). Subsequent builds are fast.

Agents drive the app through `.agents/skills/verify/SKILL.md`, which launches with animations off.
A change to anything that moves needs that skill's Motion section: `verify.sh launch --animated`,
`verify.sh record`, and `motion/cardframe.py`.

## First-Run Onboarding

The **WorkoutTracker** scheme opens a seeded Session fixture and never reaches onboarding. To see it, run the **Copy of WorkoutTracker** scheme, which runs live, on a fresh install:

1. **Sign in with Google.** A Safari sheet opens for OAuth. Use an account with access to the training Sheet.
2. **Pick the spreadsheet** from the list, or tap **Paste a URL instead** and paste the full Sheet URL. A bad URL shows an inline error.
3. On success the app opens the Session.

## Resetting State

To start fresh under **Copy of WorkoutTracker** (re-trigger onboarding):

- **Delete the app** from the simulator home screen → reinstall via Cmd+R
