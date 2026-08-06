# Greenhouse pick coverage audit (PRD #497 slice 9)

The contract slice's audit: every surface in the [17-pick manifest](README.md) has a Visual
Regression fixture under `Tests/Visual/` with recorded Day **and** Night baselines. The wholesale
re-capture the re-drive promised is verifiably complete — no pick is missing its fixture or its
baseline pair, and the snapshot target's resource phase is consistent with the committed PNGs.

Baselines live in `Tests/Visual/__Snapshots__/<Suite>/<test>.1.png`. Column key: **Pick** is the
ground-truth render in this directory; **Fixture** is the `@Test` that renders the surface;
**Day / Night** are the recorded baseline PNGs.

| # | Pick (manifest) | Appearance(s) | Fixture (suite · test) | Day baseline | Night baseline |
|---|---|---|---|---|---|
| 1 | Session stage (living stage) | Day + Night | `SessionViewVisualTests.seededSessionView…` | `seededSessionViewMatchesVisualBaseline` | `seededSessionViewMatchesNightVisualBaseline` |
| 2 | Active Set Card input block | Day (+ Night) | `ActiveSetCardVisualTests.activeSetCard…` | `activeSetCardMatchesVisualBaseline` | `activeSetCardMatchesNightVisualBaseline` |
| 3 | Superset stage | Day + Night | `SupersetStageVisualTests.supersetStage…` | `supersetStageMatchesVisualBaseline` | `supersetStageMatchesNightVisualBaseline` |
| 4 | Exercise queue sheet (Superset containment) | Day (+ Night) | `SessionQueueSheetVisualTests.queueSheetBrowsing…` | `queueSheetBrowsingMatchesVisualBaseline` | `queueSheetBrowsingMatchesNightVisualBaseline` |
| 5 | Block grid, 2 days/week | Day (+ Night) | `BlockGridVisualTests.twoDayGrid…` | `twoDayGridMatchesVisualBaseline` | `twoDayGridMatchesNightVisualBaseline` |
| 6 | Block grid, 3 days/week | Day (+ Night) | `BlockGridVisualTests.threeDayGrid…` | `threeDayGridMatchesVisualBaseline` | `threeDayGridMatchesNightVisualBaseline` |
| 7 | Block grid, 6 days/week | Day (+ Night) | `BlockGridVisualTests.sixDayGrid…` | `sixDayGridMatchesVisualBaseline` | `sixDayGridMatchesNightVisualBaseline` |
| 8 | Exercise History sheet (chip ledger, volume off) | Day (+ Night) | `ExerciseHistorySheetVisualTests.exerciseHistorySheet…` | `exerciseHistorySheetMatchesVisualBaseline` | `exerciseHistorySheetMatchesNightVisualBaseline` |
| 9 | Exercise History sheet (volume chart on) | Day (+ Night) | `ExerciseHistorySheetVisualTests.exerciseHistoryVolumeChart…` | `exerciseHistoryVolumeChartMatchesVisualBaseline` | `exerciseHistoryVolumeChartMatchesNightVisualBaseline` |
| 10 | Move On ceremony | Day + Night | `SunbirdMomentsVisualTests.moveOnCeremony…` | `moveOnCeremonyMatchesVisualBaseline` | `moveOnCeremonyMatchesNightVisualBaseline` |
| 11 | Sheet-connect screen (flat calm) | Day + Night | `SunbirdMomentsVisualTests.connectScreen…` | `connectScreenMatchesVisualBaseline` | `connectScreenMatchesNightVisualBaseline` |
| 12 | Atmosphere — living paper washes | Day + Night | `AtmosphereVisualTests.livingPaper…` | `livingPaperMatchesVisualBaseline` | `livingPaperMatchesNightVisualBaseline` |

The manifest lists 17 rows because it names each **appearance** of a surface as its own row; the 12
surfaces above collapse those 17 (both Superset-stage rows → one fixture, the three block-grid
day-counts → three fixtures, etc.). Every named appearance resolves to a committed baseline — **none
missing**.

## Notes

- **Atmosphere gets a dedicated fixture.** The living-paper wash (`atmosphere2-i`/`atmosphere2-k`) is
  the `paperBackground` rendered behind every other fixture, so it was already exercised in both
  appearances transitively. This slice adds `AtmosphereVisualTests` so the pick has its **own**
  fixture and Day/Night baseline pair, making the audit literally complete rather than transitive.
- **Additional coverage beyond the manifest** (design-governed surfaces the re-drive rebuilt that the
  picks don't enumerate one-to-one): the Sunbird colophon (`SunbirdMomentsVisualTests.sunbirdColophon`,
  the one glass survivor, Day + Night), native Settings (`SettingsViewVisualTests`, Day + Night), the
  queue-sheet pairing confirmation (`SessionQueueSheetVisualTests.queueSheetPairingConfirmation`,
  Day + Night), the in-progress Exercise-History fill state, and the secondary chrome
  (`GlassBearingViewsVisualTests`: rest pill, input pills, progress header, empty state, developer
  tools) that no longer bears glass after this slice.
- **Resource phase.** The snapshot target uses Xcode 16 `fileSystemSynchronizedGroups` (PRD #501):
  `__Snapshots__` membership *is* the filesystem, so the committed PNGs and the target are consistent
  by construction — no pbxproj edit is required to add or record a baseline.
