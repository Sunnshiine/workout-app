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

The app opens to **OnboardingView** on a fresh install (no sign-in, no sheet configured):

1. **Sign in with Google** — tap the button; a Safari sheet opens for OAuth. Use your Google account that has read access to the training sheet.
2. Once signed in, a text field appears — **paste the full Google Sheet URL** (e.g. `https://docs.google.com/spreadsheets/d/<ID>/edit`).
3. Tap **Save**. The app validates the URL and extracts the sheet ID. A bad URL shows an inline error.
4. On success the app navigates to **SessionView**.

## Resetting State

To start fresh (re-trigger onboarding):

- **Delete the app** from the simulator home screen → reinstall via Cmd+R

Or from the Xcode menu: **Product → Scheme → Edit Scheme → Arguments** and add a launch argument to clear defaults on boot — or just delete and reinstall, it's faster.

## Running via xcodebuild (no Xcode GUI)

`AGENTS.md` lists the `xcodebuild build` command. Cmd+R in Xcode is the quickest way to install and
run the build.
