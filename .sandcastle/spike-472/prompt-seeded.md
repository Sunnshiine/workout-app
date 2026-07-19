# TASK — headless sighted-loop spike (issue #472, seeded variant)

You are running inside a CI spike on a GitHub Actions macOS runner with no
GUI session. Your job is to prove the sighted inner loop works end to end
here. Do not modify or commit any files tracked by git; all outputs go to the
untracked `spike-artifacts/` directory and `spike-result-seeded.json`.

Work through these stages IN ORDER. If a stage fails, record the failure and
still attempt later stages that don't depend on it. Keep going — partial
evidence is valuable.

1. **Probe**: check whether your tools include names starting with
   `mcp__XcodeBuildMCP__` and `mcp__context7__`. If XcodeBuildMCP is absent,
   write the result file (step 6) immediately and stop.
2. **Boot**: list simulators and boot `iPhone 17 Pro` (headless mode is on —
   no Simulator window will appear; that is expected). Do not use any
   keyboard-shortcut tools at any point.
3. **Build & run**: build the `WorkoutTracker` scheme for that simulator and
   launch the app with launch arguments `-UITEST_FIXTURE true -UITEST_SESSION true`
   (fixture mode — deterministic local data, no live Google Sheets).
4. **See & touch**: screenshot the screen the app opens on and save it to
   `spike-artifacts/01-launch-light.png`. Use `describe_ui` to find one
   tappable element, tap it, and screenshot the result to
   `spike-artifacts/02-after-tap-light.png`.
5. **Night check**: switch the simulator to dark appearance, screenshot to
   `spike-artifacts/03-dark.png`.
6. **Report**: `Read` each PNG you captured and confirm it shows app UI (not
   a black/empty frame). Then write `spike-result-seeded.json` in the current
   directory:

```json
{
  "variant": "seeded",
  "xcodebuildmcpLoaded": false,
  "context7Loaded": false,
  "mcpToolSample": [],
  "bootOk": false,
  "buildRunOk": false,
  "screenshotOk": false,
  "tapOk": false,
  "darkModeOk": false,
  "screenshotsShowRealUI": false,
  "notes": "one short paragraph: what worked, what failed and why, any headless quirks"
}
```

Set each boolean from what actually happened. Be precise in `notes` — this
verdict gates whether the whole agent pipeline adopts this mechanism.
