# Session View Prototypes — Implementation Notes

> **Status: RESOLVED — Stage shipped.** Stage won and is now the one production
> Session View (ADR-0011, PRD #304). The Developer Tools "Session View Lab"
> switcher and the other three variants have been deleted; this file is kept as
> the record of *why* Stage won. The "how to flip between variants" instructions
> below are historical — the lab no longer exists.

## The question being answered

Feedback driving this exploration:

- The logging flow itself (Active Set Card → Smart Value Pills → Log) is good — keep it.
- The Session View feels cluttered and overwhelming; it should be calm, peaceful,
  confident while logging.
- Only one card/exercise should be in focus at a time.
- The header HUD is good (segments, remaining-set count, Block view access) — keep it.
- Liquid Glass preferred.

## How to flip between variants

**Settings → Developer Tools → Session View Lab.** Pick a variant; the Session
View re-renders immediately and the choice persists across launches
(`UserDefaults` key `sessionPrototypeVariant`). `Production` restores the
shipping view.

For deterministic fixture runs the launch argument `-SESSION_PROTOTYPE <variant>`
(e.g. `-SESSION_PROTOTYPE stage`) overrides the stored choice without writing it.

## The variants

Every variant keeps: the `SessionProgressHeader` glass HUD pinned on top (with
the overpull-to-Settings gesture), the unchanged `ActiveSetCard` +
`SmartValuePills` logging flow, `LoggedSetReviewCard` review/edit, skip/delete,
the rest pill, sync banner, Move On, and the palette/glass vocabulary.

They disagree about **structure** — what surrounds the one thing you're doing:

| Variant | Structure | Calmness bet |
| --- | --- | --- |
| `focusStack` **Focus Stack** | Same vertical scroll, but only the focused Exercise is expanded; every other Exercise is a slim glass row (name + per-set progress dots). Tap a row to focus it. | Clutter comes from *expanded* neighbours; collapsing them keeps full-session visibility without noise. |
| `pager` **Pager** | One Exercise per horizontal page, snap paging, page dots under the header. Auto-advances when logging flows into the next Exercise. | A page boundary is a hard wall — the rest of the Session physically can't crowd you. Swiping is browsing. |
| `stage` **Stage** | No list at all. One "now playing" surface: Exercise name, coach note, Last Performed, the Active Set Card, set dots, an up-next hint. Full queue lives in a sheet. | Maximum calm: the screen shows the single action and nothing else. Orientation is on demand, not ambient. |
| `rail` **Rail** | A pinned chip rail under the header (one chip per Exercise with a progress reading); below it, only the focused Exercise. Tap chips to switch. | Persistent whole-session orientation in ~40 pt, while the body stays single-exercise. |

## Decisions & deviations log

- **Sub-shape A (existing route).** Variants render inside the real
  `SessionView` against the live coordinator/stores — same data, same
  mutations — rather than a separate prototype screen, so they're judged
  against real density and real logging. The production branch is untouched;
  prototypes mount where its scroll view would be.
- **Real mutations, deliberately.** The prototype skill prefers stubbed
  mutations, but the whole point here is judging the *logging feel*, so
  variants call the same coordinator actions as production. In fixture mode
  everything is in-memory; on live data logs are real (same writes as
  production logging).
- **Coordinator reused, not forked.** Focus/advance/review semantics come from
  `SessionCoordinator.renderItems`. Variants are pure render layers on top, so
  behaviour (which set is active, what logging advances to) is identical in
  every variant.
- **`ExerciseSection` reused where the layout allows.** Focus Stack, Pager and
  Rail render the focused Exercise through the production `ExerciseSection` to
  keep the focus-morph/momentum animations. Stage composes `ActiveSetCard` /
  `LoggedSetReviewCard` directly (it deliberately drops the set-row list), so
  its set-to-set transition is a simpler slide/fade rather than the production
  momentum choreography.
- **Supersets.** Focus Stack, Pager and Rail render an active Superset item
  through the production `ActiveSupersetSection` (as one "exercise" unit —
  one page / one expanded item / one chip). Stage shows the superset surface
  as the stage. Pairing *creation* (the long-press grip flow) is disabled in
  all prototypes — `ExerciseSection`'s pairing closures are left at their
  do-nothing defaults — because the grip/target choreography assumes the full
  production list. Existing Supersets render and log fine; switch to
  Production to create one.
- **Open Exercises + override controls.** The sync banner and the Go
  back / Make Current override controls sit above all variants unchanged. The
  Open Exercises section (cross-session pending sets) renders in Focus Stack
  only; Pager/Stage/Rail omit it for now — switch to Production (or Focus
  Stack) if you need it. Worth deciding before promoting a winner.
- **Settings overpull.** The HUD's drag-to-reveal-Settings gesture works in
  all variants (it lives on the HUD itself). The *scroll*-driven overpull only
  exists in production; prototypes don't replicate scroll-geometry tracking.
- **Move On.** Focus Stack/Rail show the Move On button under the content like
  production; Pager gives it a calm final page; Stage shows it on the
  session-complete state.
- **Switcher placement.** Developer Tools gets a "Session View Lab" section
  (this is the "swap via developer tools" requirement). No floating in-app
  switcher bar: Developer Tools is two taps away via the overpull gesture, and
  a floating bar would contaminate the calm the prototypes are trying to
  evaluate.
- **Variant persistence is intentionally not in `SettingsStore`.** Throwaway
  state shouldn't touch the production settings surface; it's a private
  `@AppStorage`-style key read inside the prototype files only.

## Verification log

All checks ran on the `claude/sad-jennings-7b8cdb` worktree, iPhone 17 Pro
simulator, fixture mode (`-UITEST_FIXTURE true -UITEST_SESSION true`).

- **Build**: `xcodebuild build` green after `xcodegen generate`; SwiftLint
  reports no new warnings (one pre-existing `opening_brace` in
  `SheetWriterTests` untouched).
- **Tests**: `swift test` — 492 tests passed. `xcodebuild test
  -only-testing:WorkoutTrackerTests` — TEST SUCCEEDED.
- **Per-variant render check** (screenshots in `docs/prototypes/screenshots/`):
  - `focus-stack.jpg` — focused Exercise expanded, neighbours collapsed to
    glass rows with progress dots, header HUD pinned.
  - `pager.jpg` — one Exercise per page, page-indicator strip under the HUD.
  - `stage.jpg` — single "now playing" surface with set dots, Last Performed,
    up-next bar and queue button.
  - `rail.jpg` / `rail-after-log.jpg` — chip rail + focused Exercise; second
    shot taken after logging a set (see below).
  - `production.jpg` — regression check: with the picker on Production the
    shipping view renders unchanged.
  - `developer-tools-picker.jpg` — the Session View Lab section in
    Developer Tools.
- **End-to-end logging (Rail)**: empty weight → validation outline; typed 255
  → "Log 255×5@6" → set logged, chip flipped to ✓, focus auto-advanced to the
  next Exercise, header remaining-set count 7→6, rest pill started (1:57),
  sync banner showed "2 unsynced". Confirms the shared
  `SessionPrototypeActions` plumbing mutates exactly like production.
- **Switcher persistence**: picking a variant in Developer Tools moves the
  checkmark, survives relaunch, and drives `SessionView` immediately;
  `-SESSION_PROTOTYPE <variant>` launch-arg override verified for all four
  variants (read-only — does not overwrite the stored choice).

## Verdict

**Stage wins.** It made the strongest bet on the actual feedback — *maximum
calm* — by showing the single action and nothing else, with orientation (set
dots, the up-next bar, the queue sheet) available on demand instead of
ambiently. The other three kept some of the Session on screen at all times
(collapsed rows, adjacent pages, a chip rail), which left a low hum of clutter
that Stage removes entirely.

Productionizing Stage closed the three gaps the prototype deliberately left open:

- **Open Exercises** now surface in the queue sheet and on the completion stage,
  not just Focus Stack.
- **Superset pairing creation** moved into the queue sheet (pick an Exercise,
  then its partner) — the long-press grip flow was dropped because it assumed
  the full production list.
- **Scroll-driven settings overpull** was restored to match production; the
  header-drag overpull already worked in every variant.

The fast logging flow (Active Set Card → Smart Value Pills → Log) and the header
HUD carried over unchanged. See ADR-0011 and PRD #304 (slices #305–#311).
