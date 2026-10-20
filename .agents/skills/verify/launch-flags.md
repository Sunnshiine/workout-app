<!-- Generated from LaunchFlag in Sources/WorkoutTracker/Fixtures/LaunchFlag.swift. Do not edit.
     Regenerate: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests -->
# Launch flags

With no Scenario flag, the fixture seeds a Partially Uploaded Block parsed from the
`partial-upload` workbook scenario, the cells `workout init --scenario partial-upload` also
reads. When a launch passes more than one Scenario flag, the lowest Scenario number wins.
Every flag but `-UITEST_DISABLE_LIVE_ACTIVITIES`, `-UITEST_END_LIVE_ACTIVITIES`, and `-UITEST_LONG_CELEBRATION_QUOTE` acts only when the launch also passes `-UITEST_FIXTURE`.

| Flag | Kind | Meaning |
| --- | --- | --- |
| `-UITEST_FIXTURE` | Switch | Runs on an in-memory store, synced from the Scenario's local workbook at boot, with a faked sign-in and a Sheets client that never reaches Google. A log then flushes into that workbook, as it would into the coach's Sheet. |
| `-UITEST_SESSION` | Screen | Leaves Block Overview closed, so the app opens on the Current Session. |
| `-UITEST_DEVELOPER_TOOLS` | Screen | Opens Developer Tools in place of the Session screen. |
| `-UITEST_SETTINGS` | Screen | Opens Settings in place of the Session screen. |
| `-UITEST_ONBOARDING` | Screen | Leaves the spreadsheet unselected, so the app opens on onboarding's sheet picker. |
| `-UITEST_PERFECT_MOVE_ON_CELEBRATION` | Scenario 1 | Seeds the perfect-move-on-celebration workbook, whose Week 1 Day 1 has every Set Logged or Skipped, and requests the Move On Celebration. |
| `-UITEST_COMPLETED_OPEN_EXERCISES` | Scenario 2 | Seeds the completed-open-exercises workbook: one Week whose Day 2 has every Set Logged while Day 1's Back Squat still has a Pending Set. |
| `-UITEST_OPEN_EXERCISES` | Scenario 3 | Seeds the open-exercises workbook: one Week whose Days 1 to 3 each hold one Open Exercise with some Sets Logged. |
| `-UITEST_LONG_SESSION` | Scenario 4 | Seeds the long-session workbook: one Session of eight Exercises with only the first logged. |
| `-UITEST_FULL_BLOCK` | Scenario 5 | Seeds the full-block workbook: four Weeks of four Sessions, every one an Available Session. |
| `-UITEST_PARTIAL_UPLOAD` | Scenario 6 | Seeds the partial-upload workbook: four Weeks of four Days, eleven of them Unavailable Sessions. A launch that names no Scenario flag gets it too. |
| `-UITEST_DISABLE_ANIMATIONS` | Switch | Turns off UIKit animations and drops the animation from every SwiftUI transaction. |
| `-UITEST_DISABLE_LIVE_ACTIVITIES` | Switch | Reports Live Activities as disabled, so no Live Activity starts. |
| `-UITEST_END_LIVE_ACTIVITIES` | Switch | Ends every Live Activity still up from an earlier process at launch, so one never outlives a test session. |
| `-UITEST_PENDING_WRITE` | Switch | Logs 225x8@8 on Week 1 Day 1's BB RDL at boot without flushing it, so a sync writes it to the Scenario's own workbook and reloads the Block from it. |
| `-UITEST_OFFLINE` | Switch | Makes the fixture Sheet read as Offline after the boot, so a log stays queued and the header reads `N unsynced`. |
| `-UITEST_SLOW_SYNC` | Switch | Makes every tab list after the boot wait 20 seconds, so a sync stays in flight. |
| `-UITEST_LATE_SIGN_IN` | Switch | Restores the sign-in for 3 seconds after launch, showing onboarding meanwhile, then signs in, as restoring a Google sign-in does on a device. |
| `-UITEST_CURRENT_SESSION_OVERRIDE` | Switch | Makes Week 1 Day 3 the Current Session when the Scenario gives it Exercises, as Full Block does; otherwise the Current Session stays. |
| `-UITEST_MOVE_ON_CELEBRATION` | Switch | Requests the Move On Celebration for the Current Session. |
| `-UITEST_APPEARANCE` | Switch | Takes one of system, light, dark as the next argument and pins the appearance to it; any other value stops the app. |
| `-UITEST_LONG_CELEBRATION_QUOTE` | Switch | Shows a long fixture quote in the Move On Celebration in place of a random approved one. |
| `-UITEST_DICTATION` | Switch | Takes a transcript as the next argument and gives the Active Set Card a mic that hears it, in place of SpeechAnalyzer, which does not run in the Simulator. |
