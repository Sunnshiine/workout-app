# Design System: the Session stage components (DESIGN.md §5.1–§5.4)

Part of [DESIGN.md](../../DESIGN.md), which holds the overview, color, type, surfaces, and the
rules for every screen that these specs serve. The Sunbird is in [sunbird.md](sunbird.md) and
motion in [motion-and-haptics.md](motion-and-haptics.md). A § number names a section of
DESIGN.md or of one of its component files, which keep its numbering.

### 5.1 The Living Stage (Session stage)

The Session is a single "now playing" surface and the system's signature: one
Exercise at a time, its progress drawn as a **branch that leafs out per
logged Set**. From top: the Cadence line (muted, 11pt), the Fraunces Exercise
name leading the page, the coach note, the branch, the Last Performed
reference line, and the Active Set Card with the Log capsule. The foot holds
the queue pill and up-next preview. A long Exercise name may run to two lines,
and the branch cedes the vertical air. Past two lines it shrinks to 80%, then
truncates.

**The branch** is the page's one icon and one piece of flora — a 2px
round-cap stem where **every mark is the same slender blade**: inked per
logged Set, a **cream-filled leaf inside a green stroke** for the active Set
(logging inks it solid — the clever leaf fill), **faint ghost leaf outlines**
for what remains, and a **dashed-outline leaf for a Skipped Set** (Set dots,
circle buds, and angled future strokes are fully retired; validated at 8
Sets). Nodes anchor to a terminal at t=0.80 and step down the stem, so 2–3
Sets read as one sprig on a full-length stem. The branch stands **textless**
— no labels ride it. By day it inks in `actionDay`; at night it is moonlit
foliage with cream ribs, and the active leaf carries the page's one glow.

- **Guardrail — the plain head:** the Active Set Card's head carries a plain
  `Set 3 of 5` in Source Sans 3. Position and progress are always legible as
  text; the branch is never the only way to read them. This is the no-botany
  pressure valve — under extreme content the words still carry the page.
- **Last Performed** is a quiet muted runline anchored to the Active Set
  Card — `Block 26 · W4 D3 — 245x5@6, 255x5@7` — no "Last performed" label
  (the Set-Log shape says what it is), led on the left by a history clock
  (`clock.arrow.circlepath`) on its text baseline. It shrinks then truncates, never wraps. A
  Movement-level fallback match labels itself with the matched entry's own
  entered name in muted italic (*as "Standing Calve Raises"*). Tapping it
  opens the Exercise History sheet, with at most the subtlest disclosure
  hint. It is the sheet's only entry point, so while a short page has shed
  it the sheet is out of reach from the stage.
- **The stage foot:** a **queue pill** drawn as a `square.stack` glyph opens
  the day's Exercise queue sheet. It carries no count on screen; VoiceOver
  reads its `N of M` position as the pill's value. Beside it sits a plain
  `Up next · ` preview. The old glass up-next bar and the position label
  above the name are gone.
  While rest runs, the rest timer takes the `Up next` slot in the foot. It
  is a 24pt progress ring that drains, then the countdown in `statsValue`,
  with no container and no label. In the final five seconds both ink in
  `actionInk`. `Up next` fades out before the timer fades in, and back in
  after it leaves, so the two are never drawn at once. Rest starting and
  ending never moves the card. Measured on iPhone 17 Pro, 13 mini, and SE
  (3rd gen), the Log capsule held its y through a log, rest, and rest end,
  where an inset above the foot moved it 58pt each way.
- **While the weight is being edited** the page switches composition. The
  Active Set Card pins above the keyboard's Done toolbar with a 10pt gap, so
  the Log capsule stays in reach. The HUD, Cadence line, coach note, branch,
  and stage foot step aside. The Exercise name and Last Performed stay above
  the card only while they fit, and anything that does not fit leaves from
  the top. The rest timer steps aside with the foot and keeps counting, so the
  card's editing frame is the same with or without rest. The page returns
  when the weight field folds.
- **When the page runs short** (a sync banner, a small phone), what does not
  fit yields in a fixed order and the Active Set Card never does: first the
  air under the branch, then the branch's height, which flattens from 156pt
  to a 70pt floor; then Last Performed; then the Cadence line; then the
  coach note; and only then the branch, which leaves the Exercise name above
  the card. A Superset's drooping lateral lifts and shortens its leaves as
  the air under it closes. The sync banner comes and goes without moving the
  card or its Log capsule. On a short page Last Performed is the first line
  to leave, and with it the only entry point to Exercise History; the
  follow-up is #759.
- **When a finished Session runs short**, the Open Exercises list under the
  summary leaves when it does not fit, so Move On always fits. The queue
  sheet still lists the Open Exercises.

**The Stage Shows One Thing Rule** (carried forward). Exactly one Exercise
or Superset renders at a time. No stacked section-headed Exercises, no
scrolling Set-row list, no ambient rest-of-Session.

**Growth Is State Rule.** The branch renders what the athlete actually
logged — nothing more. Growth is performed only in the Move On ceremony;
nothing persists between Sessions as an accumulating garden, streak, or
trophy, and per-Session flora never carries between screens. A dashed leaf is honest about a Skip; a full branch marks
completion, not achievement.

**One Icon Per Page Rule.** The branch is the stage's icon budget spent.
Control and status glyphs (§1) do not draw on it.
Other pages spend theirs as sparingly (the Block grid spends its on nothing —
tiles are wordless fills).

### 5.2 Active Set Card & input block

The Active Set Card is the one soft container, ordered like the athlete's
actual entry — weight deliberate before the lift, reps and RPE reported
after:

- **Weight leads as the card's biggest number** — open, centered, ~54pt
  round steppers flanking it, a filled down triangle to step down and a
  filled up triangle to step up; tap-to-type raises the keyboard, whose
  toolbar dismisses it with a `keyboard.chevron.compact.down` glyph labelled
  Done.
- **Reps (1–100) and RPE (5–10) are side-by-side one-tap scroll rails**,
  labels below; selected chips take a cream fill with an inset action ring.
- **The weight pre-fills from the coach's number** when there is one: BW, a
  Drop from the previous Set, or a %1RM of the Training Max. For an RPE target
  it pre-fills the Load Suggestion estimated from the athlete's own Set Logs
  (ADR-0018). Reps and RPE pre-fill from the prescription when it names one
  value. A rep range such as `11-12` pre-fills its low end, though the weight
  for it is estimated at the range's midpoint.
- **The athlete sees only the estimated weight.** A basis line naming where it
  came from is a developer aid, off until Developer Tools' *Show Load Basis*
  turns it on. Mid-set, the number is the decision and its provenance is
  noise. When on, it sits directly under the weight in the athlete's own
  notation: `from 315x5@7 · W1 D2`,
  `from Set 1 today`, or `from 195x5@8 · Block 26 W4 D1` for another Block.
  When the Last Performed ladder, run without the Viewed Session, matched the
  entry at Movement level, the line ends with the entry's own name,
  `from 195x5@8 · W1 D2 as “Comp Bench Press”`. The Last Performed line above
  it includes the Viewed Session, so once a Set is logged today the two lines
  can name different entries. Whether they should is #803's open question.
  It is a `runline` in `textSecondary`, shrinks then truncates, and leaves as
  soon as the athlete changes the weight, so it never explains a number that is
  no longer on the card. Cards without an estimate carry no line.
- **No units anywhere** in the block.
- A prescription tick marks the coach's prescribed reps and RPE on the rails.
  A rep range ticks every value in it, and the Reps rail centers on its low end.

Card padding is 16 / 16 / 14; steppers hold ~54pt targets, rail cells 48×44.
Invalid fields mark themselves with `danger` on the specific bad field only;
disabled states reduce opacity, not hue.

**The Card Holds Still Rule.** The Active Set Card is the surface the
athlete touches most, so its box never animates and never changes size. A
log, a skip, a Superset switch, a branch-node tap, a review opening or
closing, rest, and sync all leave its frame where it was. Its values change
in the next frame, with no crossfade. Every mode draws the same rows: the
head, the weight, the rails, and the action capsule. A mode changes what a
row says, never whether the row is there. Saved and Clear sit in the head's
trailing slot, as does the mic on a Pending Set being logged. A Set written
by speech stays on the card with Saved and Clear for four seconds, its values
and action capsule disabled because only Clear changes it, then the card
moves on as a log does, at once if the athlete touches it. Its open Clear
menu stops the four seconds, and closing the menu without a Clear moves the
card on. While the mic listens, and after a press that wrote nothing, the
action capsule says what it heard in the Log button's frame, never aloud. A
review has no collapse control: tapping its leaf again ends it. Inside the
card, only what answers the athlete's own finger moves: the press (the Log
capsule's and the weight steppers', both §5.3's 0.97 snappy scale), the mic
glyph's system replace into its listening fill and back, the rail recentring,
and the hold-to-skip fill. A Superset switch is told above the card, by the
Exercise name line and the active leaf. While the weight is edited, the card
rides above the keyboard in one piece at the same size (§5.1).

**Inert-Space All-Clear Rule** (carried forward). Tapping inert stage
background clears transient UI — dismisses keyboard editing and transient
utility state — without swallowing real controls.

### 5.3 Log capsule

A full-capsule action button: green fill (`actionDay` / `actionNight`),
cream text, previewing the exact Set Log about to be written. Day carries a
soft green drop shadow; night a soft green light. **The press** scales the
capsule to 0.97 on a system snappy spring (0.16s) from touch-down until the
finger lifts or the skip commits; only the scale moves, so the title still
cuts to the next Set. **Hold-to-skip** fills
with a muted overlay and reveals the Skip affordance (reveal 250ms, commit
850ms); a skipped state renders transparent with muted text and a 1.5px
dashed stroke — the dashed "empty bed" vocabulary.

### 5.4 Superset stage — one plant, two branches

A Superset draws as a **single forked stem** — still the page's one icon.
The Exercise that comes first in Session order climbs the stem, and the
other droops off it as a shorter lateral (1.6px). Each Exercise keeps its
arm for the whole Superset. The focused arm carries full pigment and alone
carries the cream-filled active leaf (**the active leaf rides the
focus**). Alternation is one active leaf settling and one waking — never a
branch redraw. A log inks the leaf in place on its own arm, and the
partner's bud wakes on the other.

The focus tie is **tone coupling**: by day the partner's whole branch and
its Fraunces **partner name line** (the manual focus switch), led by a fork
glyph (`arrow.triangle.branch`) on the name's first baseline, carry
foliage green while full pigment stays with the focus; at night — where
foliage *is* the leaf pigment — the partner subordinates by **translucency**
instead (foliage @ 0.55). Day quiets by pigment, night by translucency.
The partner name line holds one line and truncates, so under a two-line
Exercise name the branch keeps its room on an SE. Tapping it brings the
partner's whole name to the stage.

Coach note, Last Performed, and the Active Set Card follow the focus (the
card head stays plain `Set N of M`); the foot's up-next names the partner's
next Set. In the queue sheet, glyphs carry pairing, not words, and every
glyph is the stage's forked stem drawn small, in four forms. **Offer**
dashes the lateral, **bud** is the lateral alone reaching for a plus,
**joined** is the full fork, and **split** snaps the lateral off at the
joint.

At rest a round icon button sits in the header's top right, a 46pt pill-fill
circle with a hairline pill stroke, holding the offer stem in action ink. It
begins pairing from the Exercise on stage, and it is absent when that
Exercise cannot pair. No row carries a pair glyph. While pairing, the title
stays "This Session" and the same circle holds a grey X that cancels. The
source row takes a pale action-ink capsule with a 2px action-ink outline and
the offer stem. Each eligible row shows the bud, the chosen partner fills and
shows the joined fork, and an ineligible row dims with no glyph.

A Superset row reads "Back Squat + Bench Press" on a surface capsule behind a
joined stem in action ink. Its trailing grey split stem is **Unlink**, and it
returns both Exercises to the queue. While pairing, a Superset row dims like
an ineligible row and hides Unlink without giving up its space. Every row
highlight is a capsule, since a soft-radius rectangle draws flat ticks on a
row this short (#870). The header holds one height whether it shows the
button, the X, or nothing, so the title never moves (operator rulings
2026-10-11 and 2026-10-12: self-describing icons over words, V3's stem in
V1's icon-only header button). The queue sheet itself is living paper (§2).
A row's Exercise name runs two lines at most, so the queue reads whole a
name the stage truncated.
