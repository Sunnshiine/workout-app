# Sound Recon — aicodingdictionary.com UI Sound Effects

Investigation date: 2026-07-30. All artifacts referenced below live in this directory
(`bundles/` = downloaded JS, `0v7_pretty.js` = beautified sound bundle, `samples/` = decoded audio,
`analyze.py` = measurement script).

## (a) Implementation mechanism

**The sounds are NOT synthesized.** The site plays pre-recorded samples from the open-source
[**snd-lib v1.2.4**](https://github.com/snd-lib/snd-lib) UI-sound library ("SND", kit **SND01 "sine"**),
delivered as a single **audio sprite MP3 from jsDelivr** and played via the Web Audio API
(`AudioBufferSourceNode` + `GainNode`, offset/duration selected from a sprite map).

### Evidence

**1. Sprite source URL and kit registry** — `bundles/0v7~_u7t~ujuk.js` (beautified: `0v7_pretty.js:711-736`):

```js
let w = Object.freeze({ SND01: "01", SND02: "02", SND03: "03" });
n.KITS = w, n.KIT_INFO = Object.freeze({
  [w.SND01]: { json: o.default,
    audioSrc: "https://cdn.jsdelivr.net/gh/snd-lib/snd-lib@v1.2.4/assets/sounds/sprite/01/audioSprite.mp3" },
  ...
```

**2. Sprite map** (module `56527` in `bundles/0v7~_u7t~ujuk.js`) — start/end offsets in seconds inside the sprite:

```js
t.exports = { resources: ["./assets/sounds/sprite/01/audioSprite.ogg", ...],
  spritemap: { button:{start:0,end:.1001814058956916,loop:!1},
    ...
    tap_01:{start:30,end:30.01}, tap_02:{start:32,end:32.01}, tap_03:{start:34,end:34.01004535147392},
    tap_04:{start:36,end:36.01002267573696}, tap_05:{start:38,end:38.01},
    ...
    type_01:{start:48,end:48.010068027210885}, type_02:{start:50,end:50.01011337868481},
    type_03:{start:52,end:52.010068027210885}, type_04:{start:54,end:54.0102947845805},
    type_05:{start:56,end:56.01011337868481} } }
```

**3. Web Audio playback path** — `0v7_pretty.js:1047-1066`:

```js
_play(e, t, n) {
  let r = l._ctx.createBufferSource();
  r.buffer = this._audioBuffer;
  let o = l._ctx.createGain(),
      s = new i.default(r, o);
  s.masterVolume = this.masterVolume, s.connect(o).connect(l._ctx.destination);
  let a = this._json.spritemap[t].start,
      u = this._json.spritemap[t].end;
  if (n.loop) s.audioSrc.start(l._ctx.currentTime + n.delay, a, u);
  else {
    let e = Math.max(u - a, .1);                       // ← minimum 100 ms window
    s.audioSrc.start(l._ctx.currentTime + n.delay, a, e)
  }
```

Note `Math.max(end - start, 0.1)`: the tap/type sprite entries are nominally 10 ms, but playback
always opens a 100 ms window, so the natural decay tail after the marker is included.

**4. Random round-robin variation** — `0v7_pretty.js:640` and `1398-1405`:

```js
n.TAP_SOUND_KEYS  = ["tap_01","tap_02","tap_03","tap_04","tap_05"],
n.TYPE_SOUND_KEYS = ["type_01","type_02","type_03","type_04","type_05"],
...
_playRandom(e, t = {}) { ...
  this.play(e[Math.floor(Math.random() * e.length)], t)
}
```

**5. App-level triggers** — the site instantiates snd-lib once and uses exactly **two** sounds
(`0v7_pretty.js:2697-2718`, `11030`, `14142`):

```js
(N = new P.default({ easySetup: !1, muteOnWindowBlur: !0 })).load(P.default.KITS.SND01 ?? "01")
...
function A(e = 1) { if (!j && M && N) try { N.playTap({ volume: e }) } catch {} }
```

| Event | Sound |
|---|---|
| Clicking links/buttons (AI Hero badge, copy-to-clipboard, node cards, various `onClick`s → `A()`) | random `tap_01..05`, volume 1 |
| Focused dictionary entry changes (`e.focusedSlug !== t.focusedSlug && A()`) | random `tap_01..05` |
| Un-muting sound (`t || (I(), A())`) | random `tap_01..05` |
| Typing in the search field (`onChange` → `N.playType({ volume: 1 })`) | random `type_01..05` |

A `localStorage["snd-muted"]` flag gates everything; the whole kit fades out over 0.3 s on window
blur (`muteOnWindowBlur: true`, `_fadeByWindowEvent(0, .3)`).

## (b) Measured parameters per sound

Sprite decoded to 44.1 kHz mono WAV, each entry sliced at its sprite offset with a 100 ms window
(matching the player's behavior), analyzed with `analyze.py` (numpy/scipy: peak-normalized FFT with
Hann window, 2 ms peak-envelope frames). All samples peak at 0.534 full scale (≈ −5.4 dBFS).

| Sound | Effective duration | Attack (to peak) | Decay to −20 dB | 5 strongest spectral peaks Hz (rel. amplitude) |
|---|---|---|---|---|
| tap_01 | 9.1 ms | 0.9 ms | 3.4 ms | 1330 (1.00), 1160 (0.75), 1000 (0.34), 890 (0.13), 70 (0.12) |
| tap_02 | 6.3 ms | 0.2 ms | 1.6 ms | 70 (1.00), 980 (0.28), 230 (0.12), 340 (0.05) — "thump" variant |
| tap_03 | 8.0 ms | 0.6 ms | 4.4 ms | 1280 (1.00), 1420 (0.72) |
| tap_04 | 8.8 ms | 0.6 ms | 5.6 ms | 1300 (1.00), 210 (0.06), 800 (0.05) |
| tap_05 | 7.1 ms | 0.7 ms | 2.2 ms | 1350 (1.00), 1160 (0.74), 1000 (0.55), 60 (0.20) |
| type_01 | 3.4 ms | 0.8 ms | 1.3 ms | 1260 (1.00), 230 (0.40), 2520 (0.05) |
| type_02 | 3.3 ms | 0.7 ms | 1.2 ms | 1340 (1.00), 240 (0.37) |
| type_03 | 3.2 ms | 0.7 ms | 1.2 ms | 1400 (1.00), 230 (0.33) |
| type_04 | 3.3 ms | 0.7 ms | 1.3 ms | 1490 (1.00), 230 (0.32), 640 (0.08) |
| type_05 | 3.4 ms | 0.7 ms | 1.6 ms | 1570 (1.00), 230 (0.32), 650 (0.08), 790 (0.06) |

Envelope shape (2 ms peak frames, e.g. tap_04): `0.53 0.20 0.10 0.06 0.02 0 ...` — i.e. an
essentially instantaneous attack followed by a fast exponential decay; the whole sound is a
sub-10 ms "wooden tick". The *type* variants are the same idea, half as long, with the center
frequency stepping up 1260 → 1570 Hz across the five variants (a subtle rising pitch as you type,
since variants are picked at random the effect reads as gentle pitch jitter).

## (c) Vanilla Web Audio replica functions (no libraries)

These synthesize the measured character: exponential-decay sine partials at the measured
frequencies, sub-millisecond attack, matched peak level. `tap()` and `type_()` pick a random
variant, mirroring `_playRandom`.

```js
const ctx = new (window.AudioContext || window.webkitAudioContext)();

/** One exponentially-decaying sine partial. */
function partial(t0, freq, amp, decaySec, durSec) {
  const osc = ctx.createOscillator();
  osc.type = "sine";
  osc.frequency.value = freq;
  const g = ctx.createGain();
  // ~0.7 ms attack to peak, then exponential decay (measured: −20 dB in 1–6 ms)
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.exponentialRampToValueAtTime(amp, t0 + 0.0007);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.0007 + decaySec);
  osc.connect(g).connect(ctx.destination);
  osc.start(t0);
  osc.stop(t0 + durSec);
}

// Measured variants: [ [freq, relAmp] partials, decay-to-floor seconds ]
const TAPS = [
  { partials: [[1330, 1.0], [1160, 0.75], [1000, 0.34], [890, 0.13], [70, 0.12]], decay: 0.006 },
  { partials: [[70, 1.0], [980, 0.28], [230, 0.12], [340, 0.05]],                 decay: 0.004 },
  { partials: [[1280, 1.0], [1420, 0.72]],                                        decay: 0.007 },
  { partials: [[1300, 1.0], [210, 0.06], [800, 0.05]],                            decay: 0.008 },
  { partials: [[1350, 1.0], [1160, 0.74], [1000, 0.55], [60, 0.20]],              decay: 0.005 },
];
const TYPES = [
  { partials: [[1260, 1.0], [230, 0.40], [2520, 0.05]], decay: 0.0025 },
  { partials: [[1340, 1.0], [240, 0.37]],               decay: 0.0025 },
  { partials: [[1400, 1.0], [230, 0.33]],               decay: 0.0025 },
  { partials: [[1490, 1.0], [230, 0.32], [640, 0.08]],  decay: 0.0025 },
  { partials: [[1570, 1.0], [230, 0.32], [650, 0.08], [790, 0.06]], decay: 0.0025 },
];

function playVariant(v, volume = 1) {
  const t0 = ctx.currentTime;
  const peak = 0.534 * volume;                       // measured sample peak
  const norm = v.partials.reduce((s, [, a]) => s + a, 0);
  for (const [freq, rel] of v.partials)
    partial(t0, freq, (peak * rel) / norm, v.decay, 0.1);   // 100 ms window, like snd-lib
}

/** Click / selection sound — random of 5 variants (site: N.playTap({volume:1})). */
function tap(volume = 1)  { playVariant(TAPS[Math.floor(Math.random() * TAPS.length)], volume); }

/** Keystroke sound — random of 5 variants (site: N.playType({volume:1})). */
function type_(volume = 1) { playVariant(TYPES[Math.floor(Math.random() * TYPES.length)], volume); }
```

Wire-up to match the site: call `tap()` on button/link clicks and when the focused item changes;
call `type_()` on every text-input `onChange`; gate both behind a `localStorage["snd-muted"]`
flag; on `window` blur fade a master gain to 0 over 0.3 s and back to 1 on focus.

For a **bit-exact** replica, skip synthesis and do what the site does: fetch
`https://cdn.jsdelivr.net/gh/snd-lib/snd-lib@v1.2.4/assets/sounds/sprite/01/audioSprite.mp3`,
`decodeAudioData` it, and `bufferSource.start(when, spriteStart, 0.1)` using the sprite offsets
quoted in section (a) (taps at 30/32/34/36/38 s, types at 48/50/52/54/56 s). Local decoded copies
are in `samples/`.
