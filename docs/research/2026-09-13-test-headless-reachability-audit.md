# UI and component tests: what is headless-reachable today (audit)

Wayfinder ticket #522 · 2026-09-13 · Research audit, code as of this date.
Scope: every XCTest method under `Tests/UI/` and every Swift Testing suite under
`Tests/Component/`, classified by whether the asserted behaviour can be produced
without a view. **This document records findings only; it proposes no deletions
and no test moves — those are separate tickets.**

Terminology follows `CONTEXT.md`: Current Session, Move On, Move On Celebration,
Open Exercises, Superset, Block Overview, Available / Unavailable Session, Last
Performed, Set Log. Test-layer vocabulary follows `docs/TESTING.md:83-113`.

---

## 0. Classification key and method

| Class | Meaning |
|---|---|
| **1 · Headless now** | The asserted behaviour is produced by a store / coordinator / presentation struct / parser in the SPM library target (`Package.swift:8-21` — everything under `WorkoutTracker/` except `Views`, `LiveActivity`, `Sheets/GoogleAuth.swift`, `WorkoutTrackerApp.swift`). What the UI test adds on top is only "a real control reached that call". |
| **2 · Headless after a known move** | The decision the test asserts lives in view code today, but is not inherently UI. The table names the view code that would need to move. |
| **3 · Genuinely UI-level** | Real-control hittability, keyboard focus, gestures, sheet/alert presentation, accessibility-tree shape, appearance switching. A headless test can cover the *state* behind it (noted), but not the assertion itself. |

Each test gets one primary class, chosen by the assertion that would be left
uncovered if every library-reachable part were tested headlessly. Mixed tests
carry a "residue" note.

Fixture column: `WorkoutUITestFixture` case from `Tests/UI/WorkoutUITestSupport.swift:1-25`
plus any `WorkoutUITestFixtureOption` (`:29-33`); the flag→scenario expansion is in §4.

---

## 1. `Tests/UI/` — 22 XCTest methods across 9 classes

Class-level split per `docs/TESTING.md:115-138`: `WorkoutTrackerUISmokeTests` and
`PartiallyUploadedBlockUISmokeTests` are the Ralph smoke selector; the other seven
classes are the manual UI Interaction Suite.

### 1.1 `WorkoutTrackerUISmokeTests` (`Tests/UI/WorkoutTrackerUISmokeTests.swift`) — 4 tests

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testCurrentSessionLogsFirstSetAndAdvancesActiveSet` (`:5-18`) | **1** | RPE chip → `SmartValuePillsForm.rpeText`, log title → `SmartValuePillsForm.logButtonTitle` / `makeLog()` (`WorkoutTracker/Progress/SmartValuePillsForm.swift:127`); pre-filled 237.5 → `LoadSuggestionEngine.suggest` (`WorkoutTracker/LoadSuggestionEngine.swift:17`); log + advance → `SessionCoordinator.log(_:as:animateFocus:)` (`WorkoutTracker/Progress/SessionCoordinator.swift:281`) → `advanceAfterLog` (`:258`) and `WorkoutStore.log` (`WorkoutTracker/Stores/WorkoutStore.swift:304`); "Set 1, 237.5x5@6" row → `SetRowPresentation` (`WorkoutTracker/Progress/ActiveSetPresentation.swift:120`); "Set N of 3" → `SessionStagePresentation.ordinal(of:in:)` (`WorkoutTracker/Progress/SessionStagePresentation.swift:234`). Residue: a real tap on `log-active-set-button` (`WorkoutTracker/Views/SmartValuePills.swift:489`). | `.currentSession` + `.disableCelebrationBloom` |
| `testMoveOnAdvancesToNextExercise` (`:21-40`) | **1** | Weight 252.5 after first log → `LoadSuggestionEngine.suggest` drop-percent path (`LoadSuggestionEngine.swift:46`); Move On → `WorkoutStore.requestMoveOnCelebration` (`WorkoutStore.swift:153`, wired from `SessionView.swift:223-226`); celebration label "Week 1, Day 1" → `MoveOnCelebrationPresentation.accessibilityLabel` (`WorkoutTracker/Progress/MoveOnCelebrationPresentation.swift:13`); tap → `WorkoutStore.dismissMoveOnCelebration` (`:166`) → `advance(after:)` (`:178`) via `SessionProgressTracker.moveOnDestination` (`WorkoutTracker/Progress/SessionProgressTracker.swift:113`); next Session's "Bench Press" comes from `uiLaunchSession(1,2)` (`WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift:321-322`). Residue: queue sheet presentation (`SessionStageView.swift:75`) and celebration overlay tap (`SessionView.swift:74-80`). | `.currentSession` + `.disableCelebrationBloom` |
| `testCurrentSessionOverrideControlsReturnToCurrentSession` (`:43-59`) | **1** | Tile tap → `WorkoutStore.show(week:day:)` (`WorkoutStore.swift:125`, called from `BlockOverviewView.swift:148`); Go Back / Make Current visibility → `WorkoutStore.isViewingLiveEdge` (`:54`, branched at `SessionView.swift:34`); Go Back → `WorkoutStore.showCurrent()` (`:130`, `SessionView.swift:38`); location label → `SessionProgressHeaderPresentation` (`ActiveSetPresentation.swift:189`). Residue: the `navigationDestination` push into Block Overview (`SessionView.swift:84-87`, binding at `:331-337`) and the "Block 27" nav bar. | `.currentSession` + `.disableCelebrationBloom` |
| `testSettingsPendingWriteSignOutConfirmation` (`:62-78`) | **2** | The gate "pending writes ⇒ ask; confirm ⇒ discard, then sign out" is private view code: `SettingsView.requestSignOut` (`WorkoutTracker/Views/SettingsView.swift:210-221`, `sync.hasPendingWrites()` at `:212`) and `signOutNow` (`:223-234`, `discardPendingWrites` at `:225`, `settings.signOut()` at `:232`), driven by `@State isSignOutConfirmationPresented` (`:104`). The library already has the exact same shape for sheet switching — `SettingsSheetSwitchStore.requestSwitch` / `confirmPendingSwitch` (`WorkoutTracker/Stores/SettingsStore.swift:257-305`) — so a `SettingsSignOutStore` beside it would make this headless. Library pieces reachable now: `SyncCoordinator.hasPendingWrites` (`WorkoutTracker/Stores/SyncCoordinator.swift:22`), `discardPendingWrites` (`:47`), `SettingsStore.signOut` (`SettingsStore.swift:94`). Note `GoogleAuth.signOut()` (`SettingsView.swift:231`) is excluded from the library (`Package.swift:16`) and would need injection. Residue: the `.alert` itself (`SettingsView.swift:102-112`). | `.settings` + `.pendingWrite` |

### 1.2 `WorkoutTrackerInteractionUITests` (`Tests/UI/WorkoutTrackerUITests.swift`) — 9 tests

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testActiveSetFieldFocusDismissesWithoutCardCancel` (`:5-24`) | **3** | Keyboard focus: `@FocusState weightFieldFocused` (`WorkoutTracker/Views/SmartValuePills.swift:23`), `.task(id: isEditingWeight)` (`:82-84`), fold-on-blur (`:88-90`); tap-to-dismiss on the stage root → `SessionStageView.dismissKeyboard` via `UIApplication.sendAction(resignFirstResponder)` (`WorkoutTracker/Views/SessionStageView.swift:73-74`, `:298-302`). No library state is asserted beyond "Set 1 of 3" still on stage. | `.currentSession` + `.disableCelebrationBloom` |
| `testActiveSetLogButtonSubmitsOnFirstCenterTapWhileWeightFieldIsFocused` (`:27-49`) | **3** | The regression guarded is touch/first-responder ordering: `submitLog` calls `dismissFieldUI()` at action time, not touch-down (`SmartValuePills.swift:230-241`, comment `:231-234`), with `.onTapGesture(perform: logTap)` (`:484`) and `suppressNextLogTap` (`:579-585`). State behind it (title "Log 230×5@6", resulting `SetLog`) is class 1 via `SmartValuePillsForm.logButtonTitle` / `makeLog()` (`SmartValuePillsForm.swift:127`) and `SessionCoordinator.log` (`SessionCoordinator.swift:281`), already covered by `Tests/Component/SmartValuePillsFormTests.swift:157`. | `.currentSession` + `.disableCelebrationBloom` |
| `testTapOnNonInteractiveStageContentDismissesKeyboard` (`:52-70`) | **3** | Same dismiss path: stage-root `.contentShape(Rectangle()).onTapGesture(perform: dismissKeyboard)` (`SessionStageView.swift:73-74`); the tapped `stage-exercise-name` is plain `Text` (`SessionStageView.swift:145`, `ActiveSupersetSection.swift:101`). The retained "Weight, 230" value is form state (class 1) but the assertion is about *not* logging on a text tap. | `.currentSession` + `.disableCelebrationBloom` |
| `testDeveloperToolsRouteLoadsFromSettings` (`:73-95`) | **3** | Route smoke: `NavigationLink` row `settings-developer-tools-row` (`SettingsView.swift:70`) → `DeveloperToolsView` (`.navigationTitle("Developer Tools")` `WorkoutTracker/Views/DeveloperToolsView.swift:31`), sections at `:49`, `:120`, `:160`, buttons `:129`, `:139`, back via nav bar. Section *contents* are class 1 and already headless: `WorkoutStore.currentSessionDebugInfo` (`WorkoutStore.swift:60`) and `SyncCoordinator.pendingWriteDiagnostics` (`WorkoutTracker/Stores/DeveloperToolsDiagnostics.swift:353`) — but this test asserts only titles and existence. | `.settings` + `.pendingWrite` |
| `testBuildIdentityFooterShowsAndCopiesOnTap` (`:98-109`) | **3** | "local build" in the label → `BuildIdentity.compactLine` (`WorkoutTracker/Models/BuildIdentity.swift:6`; class 1, covered by `Tests/Unit/BuildIdentityTests.swift:54`). The tap → "Copied" swap is `@State didCopy` + `UIPasteboard.general.string` (`WorkoutTracker/Views/BuildIdentityFooter.swift:8`, `:17`, `:29-30`), which is UIKit-only. | `.settings` + `.disableCelebrationBloom` |
| `testOpenExerciseMakeupFlowShowsLastPerformedAndLogsSet` (`:112-133`) | **1** | Open Exercise list → `WorkoutStore.openExercises` (`WorkoutStore.swift:55`) / `SessionProgressTracker.openExercises` (`SessionProgressTracker.swift:173`); row tap → `SessionView.showSourceSession` → `WorkoutStore.show(week:day:)` (`SessionView.swift:143-147`); Go Back / Make Current → `isViewingLiveEdge` (`:54`); "Last Performed 245x5@6, 255x5@7 … Block 26 · W4 D3" → `LastPerformedCardPresentation` (`ActiveSetPresentation.swift:307`) fed by `LastPerformedLookupStore`, seeded from `WorkoutFixtureScenarios.lastPerformedBackSquat()` (`WorkoutFixtureScenarios.swift:74-82`); "Log 252.5×5@7" → `LoadSuggestionEngine` + `SmartValuePillsForm`; log → `SessionCoordinator.log`. Residue: queue sheet presentation and row hittability (`SessionQueueSheet.swift:46-50`). | `.currentSession` + `.disableCelebrationBloom` + `.openExercises` |
| `testCompletionStageListsOpenExercisesAndNavigatesToSource` (`:136-152`) | **1** | "Session complete" is rendered when `SessionStagePresentation.stageItem(in:focusID:)` returns nil (`SessionStagePresentation.swift:137`; branch at `SessionStageView.swift:214`) with `completionSummary` (`:178`, rendered `:218`); Open Exercises list → `WorkoutStore.openExercises` (`:55`), `OpenExercisesSection` at `SessionStageView.swift:223`; `move-on-button` presence → `WorkoutStore.canMoveOn` (`:49`); tap → `showSourceSession` → `WorkoutStore.show` (`SessionView.swift:143-147`). Residue: hittability only. | `.completedSessionWithOpenExercises` + `.disableCelebrationBloom` |
| `testSettingsRevealGestureOpensSettings` (`:155-174`) | **3** | Overpull gesture reveal (`revealSessionControlsAndSettingsButton` `:272-293`, drag helpers `:296-322`) → `session-controls-settings-button` (`WorkoutTracker/Views/SessionProgressHeader.swift:134`) gated by `canRevealSessionControls` (`SessionView.swift:323-325`) and `SessionSettingsOverpullState` tracking (`SessionView.swift:241-268`). Thresholds are class 1 — `SessionSettingsOverpullState` (`ActiveSetPresentation.swift:230-283`), covered by `Tests/Component/ActiveSetPresentationTests.swift:275-313`. The Settings sheet (`SessionView.swift:89-91`) and "Fixture Training Log" title (`SettingsStore.setSpreadsheet(id:title:)` `SettingsStore.swift:63`, seeded `WorkoutTrackerApp.swift:95`) are covered by `Tests/Unit/SettingsStoreTests.swift:19`. | `.currentSession` + `.disableCelebrationBloom` + `.pendingWrite` |
| `testTappingLastPerformedOpensExerciseHistorySheet` (`:177-197`) | **3** | The sheet is presented from `LastPerformedCard.onTap` (`WorkoutTracker/Views/LastPerformedCard.swift:9`, hint `:26`) → `@State historyExercise` (`SessionStageView.swift:33`, set `:113`, `:166`) → `.sheet(item:)` (`:91-99`). Sheet *content* ("Exercise History · last 5", "BLOCK 26/25", "235×5") is class 1 — `ExerciseHistorySheetPresentation` (`WorkoutTracker/Progress/ExerciseHistorySheetPresentation.swift:14`) over `lastPerformedLookup.snapshot.history(baseName:)` (`SessionStageView.swift:95`), seeded by `backSquatHistory()` (`WorkoutFixtureScenarios.swift:86-104`); covered by `Tests/Component/ExerciseHistorySheetPresentationTests.swift:26,44,302` and `Tests/Unit/ExerciseHistoryQueryTests.swift:24`. | `.currentSession` + `.disableCelebrationBloom` |

### 1.3 `WorkoutTrackerAppearanceUITests` (`Tests/UI/WorkoutTrackerUITests.swift:216-238`) — 1 test

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testSettingsAppearancePickerIsReachableAndWired` (`:218-232`) | **3** | Segmented control reachability (`settings-appearance-picker`, `SettingsView.swift:24-30`) and two taps with no post-tap assertion. The option set (System / Light / Night, no Black / Mint Green / Blue Light) is class 1 — `AppearancePreference.allCases` (`SettingsStore.swift:7`, iterated at `SettingsView.swift:25`) — already covered by `Tests/Unit/SettingsStoreTests.swift:87` and `Tests/Component/ThemeTests.swift:73,120`. | `.settings` |

### 1.4 `WorkoutTrackerOnboardingSwitchUITests` (`Tests/UI/WorkoutTrackerUITests.swift:240-262`) — 1 test

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testOnboardingSheetSelectionAutoSyncsAndReplacesStaleCachedBlock` (`:245-261`) | **2** | Library chain exists end-to-end: `SheetPickerStore.select` (`SettingsStore.swift:387`) → validation (`:400-424`) → `onValidatedSelection` → `SettingsSheetSwitchStore.requestSwitch(to: SheetSelection)` (`:257`) → `SyncCoordinator.sync` (`SyncCoordinator.swift:100`) → `workout.reload()`. The list ("Replacement Training Log") and the replacement grid ("Replacement Squat") come from `FixtureSheetsClient` (`WorkoutTracker/Fixtures/UITestFixture.swift:144-174`). **What is view-only is the composition**: `OnboardingView` builds the picker with `onValidatedSelection: { await commitSelection(SheetSelection($0)) }` (`WorkoutTracker/Views/OnboardingView.swift:25-29`), owns the switch store (`:173-178`) and maps `SettingsSheetSwitchResult` to alerts in `commitSelection` (`:192-211`); `SheetPickerView` constructs `SheetPickerStore` in `.task` (`:264-273`). Moving that glue into an onboarding selection store in `Stores/` makes it class 1. "Choose your training sheet" gating → `AppEntryDestination` (`WorkoutTracker/Progress/OnboardingPresentation.swift:1`; `OnboardingView.swift:52-58`, `RootView.swift:64-70`) is class 1 already. Residue: `RootView` re-routing to `SessionView` on `settings.spreadsheetId` change (`RootView.swift:20-24`). Headless coverage of the stale-Block rule: `Tests/Unit/SettingsStoreTests.swift:450`, `:539`; picker callback: `Tests/Unit/SheetPickerStoreTests.swift:75`. | `.onboarding` + `.disableCelebrationBloom` |

### 1.5 `WorkoutTrackerLongSessionUITests` (`Tests/UI/WorkoutTrackerUITests.swift:357-416`) — 2 tests

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testLongSessionStageAdvancesAfterLogAndShowsUpNext` (`:359-382`) | **1** | Up-next label → `SessionStagePresentation.upNextItem(after:in:)` (`SessionStagePresentation.swift:160`; rendered `SessionStageView.swift:246`, id `:266`); advance → `SessionCoordinator.log` → `advanceAfterLog` (`SessionCoordinator.swift:281`, `:258`); the 8-exercise order is `longSessionExercises()` (`WorkoutFixtureScenarios.swift:281-298`). Residue: typing 225 into the weight field (keyboard) and the header tap to fold it — incidental to the assertion. Headless coverage: `Tests/Unit/SessionStagePresentationTests.swift:166,179`. | `.longSession` |
| `testLongSessionQueueListsEveryExerciseAndJumpLandsOnStage` (`:385-410`) | **2** | "1 of 8" → `SessionStagePresentation.queueProgressLabel` (`:173`; class 1, `SessionStagePresentationTests.swift:227`). The jump is view code: `SessionStageView.jump(to:)` (`SessionStageView.swift:293-296`) = `item.nextPendingSet` (library, `SessionStageItem` at `SessionStagePresentation.swift:55-100`) → `actions.focus` → `SessionCoordinator.focus(on:)` (`SessionCoordinator.swift:270`). Two lines; a `SessionCoordinator.jump(to: SessionStageItem)` (or a `SessionStagePresentation` helper returning the target set) makes the whole assertion headless. Row enabled state is a view branch (`SessionQueueSheet.swift:113`). Residue: long-sheet scroll (`:399-405`) — class 3. | `.longSession` |

### 1.6 `WorkoutTrackerSupersetUITests` (`Tests/UI/WorkoutTrackerUITests.swift:418-465`) — 2 tests

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testQueuePairingCreatesAndDismissesSuperset` (`:420-445`) | **1** | `SessionCoordinator.beginPairing(from:in:)` (`SessionCoordinator.swift:755`, view call `SessionStageView.swift:311-313`), `handlePairingTap(on:in:)` (`:773`, view `:316-318`), `createSuperset(from:to:in:)` (`:368`), `dismissSuperset(containing:in:)` (`:375`, view `SessionView.swift:180-185`); "Pick a partner" and row roles → `SessionStagePresentation.pairingRole` (`SessionStagePresentation.swift:241`); "Back Squat + BB RDL" → superset `SessionStageItem.title` (`SessionStagePresentationTests.swift:324`); "0 of 2" → `queueProgressLabel` (`:173`). Headless coverage: `Tests/Unit/SessionCoordinatorTests.swift:472-568`, `Tests/Unit/SupersetStateTests.swift:143`. **Finding:** the tail assertions `staticTexts["SUPERSET"]` (`:438`, `:443`) and `buttons["Dismiss superset"]` (`:440`) have no source anchor — `grep -rin "dismiss superset" WorkoutTracker` returns nothing, `ActiveSupersetSection.onDismiss` is declared (`WorkoutTracker/Views/ActiveSupersetSection.swift:19`) and never invoked, and no view emits an uppercase "SUPERSET" caption. As written, the test cannot pass against this tree; the library behaviour it targets is intact. | `.currentSession` |
| `testQueuePairingCanBeCancelled` (`:448-464`) | **1** | `SessionCoordinator.beginPairing` (`:755`) then `cancelPairing` (`:764`, wired `SessionStageView.swift:88`, button `SessionQueueSheet.swift:87`); pair button reappears via `canBeginPairing` → `SessionCoordinator.canPair` (`:363`). Headless coverage: `SessionCoordinatorTests.swift:501`. Residue: sheet stays presented. | `.currentSession` |

### 1.7 `WorkoutTrackerSkipUITests` (`Tests/UI/WorkoutTrackerUITests.swift:467-487`) — 1 test

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testActiveSetCanBeSkippedWithHold` (`:469-481`) | **3** | The hold is `.onLongPressGesture(minimumDuration: policy.holdDuration …, perform: completeSkip)` (`SmartValuePills.swift:471-482`) driven by `HoldToSkipPolicy` (`ActiveSetPresentation.swift:11`, class 1, `Tests/Component/ActiveSetPresentationTests.swift:18-83`). The resulting state ("Set 1, skip", "Set 2 of 3") is class 1 — `SessionCoordinator.skip` (`SessionCoordinator.swift:312`), `WorkoutStore.skip` (`WorkoutStore.swift:334`), `SetRowPresentation` skipped (`ActiveSetPresentationTests.swift:124`), `ActiveSetFocusManagerTests.swift:230`. Only the gesture itself is UI. | `.currentSession` |

### 1.8 `PartiallyUploadedBlockUISmokeTests` (`Tests/UI/PartiallyUploadedBlockUISmokeTests.swift`) — 1 test

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testUnavailableSessionIsInertAndAvailableSessionOpens` (`:5-16`) | **2** | Tile state, label, value ("Not uploaded") and identifier are class 1 — `BlockOverviewPresentation.tile(for:in:currentSession:tracker:)` (`WorkoutTracker/Progress/BlockOverviewPresentation.swift:124-145`) over `SessionProgressTracker.tileState` (`SessionProgressTracker.swift:185`) / `isAvailable` (`:201`) / `SessionTileState.accessibilityValue` (`:18`); covered by `Tests/Component/BlockOverviewPresentationTests.swift:186`. **The inertness is a view branch**: `BlockOverviewView.dayTile` renders a non-`Button` `SessionTile` when `tile.state == .unavailable` and a `Button { show(week:day:) }` otherwise (`WorkoutTracker/Views/BlockOverviewView.swift:125-140`). Lifting an explicit "openable" property onto `BlockOverviewTilePresentation` makes the decision headless; the remaining residue ("no button with that label exists in the tree", coordinate tap does nothing) is class 3. Opening W1 D2 → `WorkoutStore.show` (`BlockOverviewView.swift:147-150`). Block seeded via the default branch of `UITestFixture.seed` (`UITestFixture.swift:126`); overview opened via `startsInBlockOverview` → `requestBlockOverviewPresentation` (`WorkoutTrackerApp.swift:80-82`). | `.partiallyUploadedBlock` |

### 1.9 `PartiallyUploadedBlockUITests` (`Tests/UI/PartiallyUploadedBlockUITests.swift`) — 1 test

| Test | Class | Library entry point / blocking view code | Fixture |
|---|---|---|---|
| `testTerminalMoveOnReturnsToAccessibleBlockGrid` (`:6-30`) | **1** | Tile → `WorkoutStore.show(week:4, day:1)` (`:125`); Make Current → `makeDisplayedSessionCurrent` (`:135`, `SessionView.swift:42`); Move On → `requestMoveOnCelebration` (`:153`); celebration label "Week 4, Day 1" and value "1 Sets, 1 Exercises, 1 Left" → `MoveOnCelebrationPresentation.accessibilityLabel` / `accessibilityValue` (`MoveOnCelebrationPresentation.swift:13`; `Tests/Component/MoveOnCelebrationPresentationTests.swift:101`); tap → `dismissMoveOnCelebration` (`:166`) → `advance` hits `.returnToBlockOverview` (`SessionProgressTracker.swift:113-119`) → `requestBlockOverviewPresentation` (`WorkoutStore.swift:184-185`). Headless coverage: `Tests/Unit/PartiallyUploadedBlockWorkoutStoreTests.swift:54`, `Tests/Unit/SessionProgressTrackerTests.swift:443`, `Tests/Unit/WorkoutStoreTests.swift:406`. Residue: the nav push back to the grid (`SessionView.swift:84-87`). | `.partiallyUploadedBlock` |

---

## 2. `Tests/Component/` — 16 suites, 191 `@Test` functions

Every file under `Tests/Component/` compiles into the `WorkoutTrackerTests` SPM
test target (`Package.swift:22-27` excludes only `UI`, `Visual`,
`Unit/GoogleAuthTests.swift`), so all 16 suites are headless-reachable **now** by
construction. The table records what each actually reaches, plus the two
platform guards and the two suites that are source-grep gates rather than
behaviour tests. Test counts are `@Test` occurrences per file.

| Suite (file) | Tests | Class | Library entry point(s) | Fixture / notes |
|---|---|---|---|---|
| `ActiveSetPresentationTests.swift` | 44 | **1** | `HoldToSkipPolicy` (`:18-83` → `ActiveSetPresentation.swift:11`), `HoldToSkipButtonPresentation` (`:85-110` → `:68`), `SetRowPresentation` (`:112-144` → `:120`), `SetCardPresentation` (`:146-181` → `:155`), `SessionFocusMorphPolicy` (`:183-229` → `Progress/SessionFocusMorphPolicy.swift:11`), `SessionProgressHeaderPresentation` (`:232-273` → `:189`), `SessionSettingsOverpullState` (`:275-315` → `:230`), `ExerciseSummaryRowPresentation` (`:317-419` → `:284`), `LastPerformedCardPresentation` (`:421-542` → `:307`) | In-memory SwiftData for the index-lookup cases (`:454-503`); no launch flag |
| `BlockOverviewPresentationTests.swift` | 9 | **1** | `BlockOverviewPresentation` / `BlockOverviewWeekPresentation` / `BlockOverviewTilePresentation.fillQuarters` (`Progress/BlockOverviewPresentation.swift:3,23,35,56`) | `WorkoutScenarios.blockOverviewWithMixedSessionStates()` (`:130`), `.partiallyUploadedBlock()` (`:186`) — same builders the UI flags seed (§4) |
| `DeveloperToolsDiagnosticsTests.swift` | 8 | **1** | `SheetWriteAuditDetails.auditDetails` (`Stores/DeveloperToolsDiagnostics.swift:11,30`), `SyncCoordinator.pendingWriteDiagnostics` / `writeTargetAuditDiagnostics` (`:353,357`), `WriteTargetAuditDiagnostic.copyText` (`:325`) | In-memory `ModelContainer` (`:214-219`) |
| `ExerciseHistorySheetPresentationTests.swift` | 25 | **1** | `ExerciseHistorySheetPresentation` (`Progress/ExerciseHistorySheetPresentation.swift:14`): grouping, chips, well, cap, volume points/seams/fractions | Pure `LastPerformedEntry` values |
| `FontPlumbingTests.swift` | 5 | **3** (UIKit-hosted) | `Theme.font` roles over registered `UIFont` families | Whole file is `#if canImport(UIKit)` (`:6-14`): runs only on the simulator host, not the macOS `swift test` pass. It is a bundle-registration check, not a state contract |
| `HistoryFillProgressPresentationTests.swift` | 2 | **1** | `HistoryFillProgressPresentation` (`Progress/HistoryFillProgressPresentation.swift:10`) | — |
| `MoveOnCelebrationPresentationTests.swift` | 9 | **1** | `MoveOnCelebrationPresentation` (`Progress/MoveOnCelebrationPresentation.swift:13`): context/title/stats/accessibility text/quote | Local session builders (`:7-15`) |
| `OnboardingPresentationTests.swift` | 4 | **1** | `AppEntryDestination` (`Progress/OnboardingPresentation.swift:1`), `OnboardingConnectPresentation` (`Progress/OnboardingConnectPresentation.swift:5`) | — |
| `RPEScalePresentationTests.swift` | 4 | **1** | `RPEScalePresentation` (`Progress/RPEScalePresentation.swift:65`) | — |
| `SetLogWireTokenGateTests.swift` | 1 | **1** (source gate) | None — greps `WorkoutTracker/**/*.swift` for a bare `"skip"` literal (`:20-40`); no `@testable import` | Reads the repo from `#filePath` (`:5-10`) |
| `SmartValuePillsFormTests.swift` | 23 | **1** | `SmartValuePillsForm` (`Progress/SmartValuePillsForm.swift:4`): prefill via `LoadSuggestionEngine`, `logButtonTitle`, `canLog`, `makeLog()` (`:127`), validation, stepping, cancel/draft | Includes the fixture's 237.5 preview (`:219-223`) |
| `SyncStatusPresentationTests.swift` | 1 | **1** | `SyncStatusBannerPresentation` (`Stores/SyncStatusBannerPresentation.swift:3`) | `WorkoutScenarios.queuedWrite()` / `.syncFailure()` (`:8-10`) |
| `ThemeTests.swift` | 37 | **1** | `Theme` (`WorkoutTracker/Theme.swift:24`): appearances, palette resolution, `-WORKOUT_THEME` launch parsing (`:109-128` → `Theme.swift:312,510`), token sheet values | Colour-component helpers are `#if canImport(AppKit)` (`:6-10`) — those tests resolve on macOS only |
| `ValueRailPresentationTests.swift` | 8 | **1** | `ValueRailChip` / `ValueRailLayout` (`Progress/RPEScalePresentation.swift:7,21`) | — |
| `WeightPillLayoutMetricsTests.swift` | 3 | **1** | `WeightPillLayoutMetrics` (`Progress/WeightPillLayoutMetrics.swift:3`) | — |
| `WorkoutGlassMigrationContractTests.swift` | 8 | **1** (source gate) | None — asserts files/strings absent from `WorkoutTracker/Views` (`:25-112`); no `@testable import` | Also asserts `MoveOnCelebrationView` does not read `UITEST_DISABLE_CELEBRATION_BLOOM` (`:93`) — see §4 |

---

## 3. Fixture plumbing: how a UI test reaches its scenario

1. `launchWorkoutApp(fixture:options:)` appends `fixture.launchArguments + options` (`Tests/UI/WorkoutUITestSupport.swift:35-45`).
2. `WorkoutTrackerApp.init` checks `UITestFixture.isEnabled` (`WorkoutTrackerApp.swift:18`), builds an in-memory container (`UITestFixture.makeContainer` `UITestFixture.swift:88-101`), a throwaway `UserDefaults` suite (`:103-107`), a signed-in `SettingsStore` titled "Fixture Training Log" (`WorkoutTrackerApp.swift:85-98`), and a `SyncCoordinator` over `FixtureSheetsClient` (`:34-40`, client `UITestFixture.swift:139-177`).
3. `UITestFixture.seed` picks exactly one Block by flag precedence (`UITestFixture.swift:115-126`), always inserts `backSquatHistory()` (`:128-130`), and adds `queuedWrite()` under `-UITEST_PENDING_WRITE` (`:131-133`).
4. `applyUITestNavigationFixtures` (`WorkoutTrackerApp.swift:75-83`) applies the override / celebration / Block Overview requests; `RootView` routes `-UITEST_DEVELOPER_TOOLS` and `-UITEST_SETTINGS` directly to those screens (`RootView.swift:11-24`).
5. `SessionView.task` only syncs when `workout.block == nil` (`SessionView.swift:92-100`), so seeded runs never hit `FixtureSheetsClient.fetchTabSnapshot` except the onboarding switch.

The headless side uses the **same Block builders**: `Tests/Support/WorkoutScenarios.swift:60-94` delegates to `WorkoutFixtureScenarios.*` (`WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift:12-54`), and `Fixtures/` is inside the SPM library target (`Package.swift:11-20` does not exclude it; guarded by `#if DEBUG` at `WorkoutFixtureScenarios.swift:1`), so `uiLaunchBlock()`, `longSessionBlock()` and `completedSessionWithOpenExercisesBlock()` are callable from `swift test` today even though `WorkoutScenarios` has no wrapper for them.

## 4. Flag → scenario table

| Launch flag | Read at | Effect | Seeded `WorkoutFixtureScenarios` scenario | Used by (Tests/UI) |
|---|---|---|---|---|
| `-UITEST_FIXTURE` | `UITestFixture.swift:11-13`; `WorkoutTrackerApp.swift:18`; `RootView.swift:12,16` | Enables fixture mode: in-memory store, faked sign-in, `FixtureSheetsClient`, skips `GoogleAuth.restorePreviousSignIn` (`WorkoutTrackerApp.swift:116-120`) | (selector for the rest) | every fixture case (`WorkoutUITestSupport.swift:9-22`) |
| `-UITEST_SESSION` | `:50-52` | Makes `startsInBlockOverview` false (`:62-64`) so no `requestBlockOverviewPresentation` fires (`WorkoutTrackerApp.swift:80-82`); app lands on `SessionView` | — | `.currentSession`, `.longSession`, `.completedSessionWithOpenExercises` |
| `-UITEST_SETTINGS` | `:35-37`; `RootView.swift:16-19` | Root is `NavigationStack { SettingsView() }` | — | `.settings` |
| `-UITEST_ONBOARDING` | `:42-44`; `WorkoutTrackerApp.swift:94-96` | Spreadsheet left unset so `AppEntryDestination == .sheetPicker`; seeded Block stays as the "stale" cache | Block per other flags (`uiLaunchBlock` with `-UITEST_FULL_BLOCK`); replacement grid from `FixtureSheetsClient.fetchTabSnapshot` (`UITestFixture.swift:157-174`) | `.onboarding` |
| `-UITEST_DEVELOPER_TOOLS` | `:31-33`; `RootView.swift:12-15` | Root is `NavigationStack { DeveloperToolsView() }` | — | **none** (no Tests/UI reference) |
| `-UITEST_FULL_BLOCK` | `:66-68`; seed `:124-125` | Seeds the 4×4 launch Block | `uiLaunchBlock()` (`WorkoutFixtureScenarios.swift:250-262`): W1D1 Back Squat + RDL, W1D2 Bench + Pull-Up, W1D3 Deadlift, all other days one accessory (`:316-329`) | `.currentSession`, `.settings`, `.onboarding` |
| `-UITEST_PARTIAL_BLOCK` | **not read anywhere** (`grep PARTIAL_BLOCK UITestFixture.swift` → none) | Marker only. The partially uploaded Block is the *default* seed when no other Block flag is present (`:126`), and Block Overview opens because `-UITEST_SESSION` is absent (`:62-64`) | `partiallyUploadedBlock()` (`:200-211`): only W1D1, W1D2, W2D1, W3D1, W4D1 have Exercises (`:331-345`) | `.partiallyUploadedBlock` |
| `-UITEST_LONG_SESSION` | `:27-29`; seed `:122-123` | Seeds a single 8-Exercise Session | `longSessionBlock()` (`:264-279`, exercises `:281-298`) | `.longSession` |
| `-UITEST_OPEN_EXERCISES` | `:19-21`; seed `:120-121` | Seeds W1 with open Back Squat, open Bench, current Deadlift Sessions | `openExercisesBlock()` (`:147-160`) | `.openExercises` option |
| `-UITEST_COMPLETED_OPEN_EXERCISES` | `:23-25`; seed `:118-119` | Seeds W1 with open Back Squat, completed Bench, pending Deadlift | `completedSessionWithOpenExercisesBlock()` (`:163-180`) | `.completedSessionWithOpenExercises` |
| `-UITEST_MOVE_ON_CELEBRATION` | `:54-56`; `WorkoutTrackerApp.swift:77-79` | Calls `workout.requestMoveOnCelebration()` at launch | Block per other flags | **none** |
| `-UITEST_PERFECT_MOVE_ON_CELEBRATION` | `:58-60`; seed `:116-117`; `WorkoutTrackerApp.swift:77-79` | Seeds the Perfect Session Block and requests the celebration | `perfectMoveOnCelebrationBlock()` (`:214-247`) | **none** |
| `-UITEST_CURRENT_SESSION_OVERRIDE` | `:46-48`; `WorkoutTrackerApp.swift:100-104` | `show(week:1, day:3)` + `makeDisplayedSessionCurrent()` at launch | Block per other flags | **none** |
| `-UITEST_APPEARANCE <system\|light\|dark>` | `:70-82`; `WorkoutTrackerApp.swift:87-89` | Presets `SettingsStore.appearance` | — | **none** in Tests/UI; parser unit-tested at `Tests/Unit/SettingsStoreTests.swift:119-146` |
| `-UITEST_PENDING_WRITE` | `:15-17`; seed `:131-133` | Inserts one queued `PendingWrite` for Back Squat W1D1 notes | `queuedWrite()` (`:60-72`) | `.pendingWrite` option |
| `-UITEST_DISABLE_CELEBRATION_BLOOM` | **not read anywhere in `WorkoutTracker/`** | No-op. Still passed by 11 UI tests via `WorkoutUITestFixtureOption.disableCelebrationBloom` (`WorkoutUITestSupport.swift:30`); `Tests/Component/WorkoutGlassMigrationContractTests.swift:93` asserts the celebration view must *not* read it | — | most Smoke / Interaction tests |
| (always) | seed `:128-130` | Three `LastPerformedEntry` rows for Back Squat | `backSquatHistory()` (`:86-104`) | every fixture |

## 5. Duplication of the `docs/TESTING.md` "Representative UI Integration Smoke" flows

The five flows are listed at `docs/TESTING.md:195-206`. "Headless owner" cites
tests under `Tests/Unit` or `Tests/Component` that already assert the same
state transition; "Not duplicated" names what only the UI test proves.

| Smoke flow (`TESTING.md`) | UI test(s) | Headless owner(s) | Not duplicated headlessly |
|---|---|---|---|
| Log first Set, next Active Set advances (`:197-198`) | `WorkoutTrackerUISmokeTests.testCurrentSessionLogsFirstSetAndAdvancesActiveSet` | `Tests/Unit/WorkoutStoreLoggingTests.swift:116` (optimistic log + queued write), `:133` (loggedAt); `Tests/Unit/SessionCoordinatorTests.swift:709` (log → advance focus → flush); `Tests/Unit/ActiveSetFocusManagerTests.swift:88` (advance within Exercise); `Tests/Component/SmartValuePillsFormTests.swift:157` (title + `makeLog`), `:211`/`:333` (RPE selection), `:219-223` (the 237.5 preview); `Tests/Component/ActiveSetPresentationTests.swift:112` (logged row); `Tests/Unit/LoadSuggestionEngineTests.swift:5-27` | Real tap on the capsule reaching `SessionView.logWithMomentum` (`SessionView.swift:164-170`) |
| Move On → dismiss Celebration → next Session/Exercise (`:199-200`) | `WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise`; `PartiallyUploadedBlockUITests.testTerminalMoveOnReturnsToAccessibleBlockGrid` | `Tests/Unit/WorkoutStoreTests.swift:342`, `:356`, `:372`, `:406`, `:422`, `:442`, `:468`, `:497`; `Tests/Unit/SessionProgressTrackerTests.swift:418-459`; `Tests/Unit/PartiallyUploadedBlockWorkoutStoreTests.swift:37`, `:54`; `Tests/Component/MoveOnCelebrationPresentationTests.swift:7`, `:56`, `:101` | Celebration overlay mount/unmount (`SessionView.swift:74-80`) and the `navigationDestination` push for `.returnToBlockOverview` (`:84-87`) |
| Block Overview → non-current Session → Make Current / Go Back → Current Session (`:201-202`) | `WorkoutTrackerUISmokeTests.testCurrentSessionOverrideControlsReturnToCurrentSession` | `Tests/Unit/WorkoutStoreTests.swift:156` (showCurrent), `:174` (show does not change current), `:187`, `:239` (makeDisplayedSessionCurrent), `:222`, `:298`; `Tests/Component/BlockOverviewPresentationTests.swift:130` (tile grid); `Tests/Component/ActiveSetPresentationTests.swift:232` (header location text) | Presence of `CurrentSessionOverrideControls` keyed on `isViewingLiveEdge` (`SessionView.swift:34-46`) and the nav round-trip |
| Settings route + pending-write sign-out confirmation (`:203-204`) | `WorkoutTrackerUISmokeTests.testSettingsPendingWriteSignOutConfirmation` | `Tests/Unit/SettingsStoreTests.swift:149` (signOut clears auth + selection); `Tests/Unit/SyncCoordinatorWriteTests.swift:348` (discard clears queued + conflicted; `hasPendingWrites` flips `:380-384`). The confirm-gate shape is tested only for **sheet switch** (`SettingsStoreTests.swift:269`, `:298`, `:323`) | **Partially duplicated.** The sign-out gate itself (`hasPendingWrites` → alert → `discardPendingWrites` → `signOut`) has no headless owner because it is private to `SettingsView.swift:210-234` (see §1.1, class 2) |
| Partially Uploaded Block: Unavailable Session inert, Available Session opens (`:205-206`) | `PartiallyUploadedBlockUISmokeTests.testUnavailableSessionIsInertAndAvailableSessionOpens` | `Tests/Component/BlockOverviewPresentationTests.swift:186` (16 tiles, W1D3 `.unavailable`, value "Not uploaded", identifier `session-tile-W1-D3`); `Tests/Unit/SessionProgressTrackerTests.swift:108`, `:121`, `:133`, `:326`, `:339` (availability and tile state); `Tests/Unit/WorkoutStoreTests.swift:174` (show) | **Partially duplicated.** "Inert" is the view branch at `BlockOverviewView.swift:125-140` (non-`Button` for `.unavailable`); no headless test asserts openability as a value (see §1.8, class 2) |

Also worth recording: the residual "real tap reaches the store" wiring in the
three fully-duplicated rows is exactly what `docs/TESTING.md:85-87` assigns to UI
Integration Smoke, so those rows are duplicated in *state* but not in *purpose*.

---

## 6. Counts

`Tests/UI/` — 22 XCTest methods (20 in the seven `WorkoutTrackerUITests.swift` /
`WorkoutTrackerUISmokeTests.swift` classes + 2 in the `PartiallyUploadedBlock*` classes):

| Class | Count | Tests |
|---|---|---|
| **1 · Headless now** | **9** | Smoke: log-first-set, move-on, override-controls · Interaction: open-exercise-makeup, completion-stage · LongSession: stage-advances-up-next · Superset: create-and-dismiss, cancel-pairing · PartiallyUploadedBlockUITests: terminal-move-on |
| **2 · Headless after a known move** | **4** | Smoke: pending-write sign-out (`SettingsView.requestSignOut`/`signOutNow`) · Onboarding: selection auto-sync (`OnboardingView.commitSelection` + picker construction) · LongSession: queue jump (`SessionStageView.jump(to:)`) · PartiallyUploadedBlockUISmokeTests: inert tile (`BlockOverviewView.dayTile` branch) |
| **3 · Genuinely UI-level** | **9** | Interaction: field-focus-dismiss, log-while-focused, tap-text-dismiss, developer-tools route, build-identity copy, settings overpull gesture, history sheet presentation · Appearance: picker · Skip: hold gesture |

`Tests/Component/` — 16 suites, 191 `@Test` functions:

| Class | Suites | Notes |
|---|---|---|
| **1 · Headless now** | **15** | 13 behaviour suites over `Progress/`, `Stores/`, `Theme.swift`; 2 source-grep gates (`SetLogWireTokenGateTests`, `WorkoutGlassMigrationContractTests`). `ThemeTests` colour assertions are AppKit-guarded (macOS host only). |
| **2 · After a move** | **0** | — |
| **3 · Genuinely UI-level** | **1** | `FontPlumbingTests` (UIKit font registration; `#if canImport(UIKit)`) |

Side findings recorded above, for follow-up tickets rather than this one:
`WorkoutTrackerSupersetUITests.testQueuePairingCreatesAndDismissesSuperset` asserts
a "SUPERSET" caption and a "Dismiss superset" button that no view emits (§1.6);
`-UITEST_DISABLE_CELEBRATION_BLOOM` and `-UITEST_PARTIAL_BLOCK` are no-op launch
arguments (§4); four fixture flags (`-UITEST_DEVELOPER_TOOLS`,
`-UITEST_MOVE_ON_CELEBRATION`, `-UITEST_PERFECT_MOVE_ON_CELEBRATION`,
`-UITEST_CURRENT_SESSION_OVERRIDE`) have no Tests/UI consumer (§4).
