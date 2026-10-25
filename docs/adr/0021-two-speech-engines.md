# Two speech engines decide a Dictation

Dictation hears the athlete through SpeechTranscriber, the SpeechAnalyzer model. On the speech
bench, prompted Whisper small (WhisperKit, `openai_whisper-small.en` with prompt p1) wrote the
correct Set for 89.4% of 2,832 held-out clips, and SpeechTranscriber for 44.0%. The bench ran on an
M-series Mac with synthetic `say` voices. No iPhone has been measured. Whisper reads a recording in
one batch after the athlete stops, and it emits nothing while they speak. Two things need words as
they arrive. Hands-free listening stops 1.2 s after the caption last changed, and the card captions
the press as the athlete speaks. Whisper alone would break both.

We run both engines. SpeechAnalyzer keeps listening live for the caption and the auto-stop, and the
transcripts it hands over when the press ends are the Live Transcript. The same microphone tap
records the press at 16 kHz, and Whisper small reads that recording once the press ends. Its
transcript is the Recording Transcript. The write policy reads the two side by side (`Hearing`),
never as one candidate list. Each engine's transcripts first go through the single-engine policy
that shipped before this decision, so an engine's alternatives settle only its own cut-off values
(CONTEXT.md, Spoken Set). A `MergeRule` then joins the two outcomes, and `EngineAgreement` names how
they compared. A press whose Speech Model is not ready has no Recording Transcript, and the
single-engine policy decides it unchanged.

**`lead` ships.** The Recording Transcript's outcome decides every press Whisper read, and the Live
Transcript decides a press Whisper did not read. That is Whisper as the bench measured it, which the
operator asked to ship as is. `gate` stays implemented. Under it the Recording Transcript still
leads, but a write the Live Transcript reads as a different Set becomes a fill the athlete confirms
with a tap. On the bench's paired rows `gate` cut out-of-sample wrong writes from 12 to 6, at about
two taps per wrong write avoided. On the locked phone a fill costs a second press, not a tap. Six
avoided writes on synthetic voices is too few to ship on, so the choice waits for recorded presses.
`liveOnly` and `recordingOnly` exist so a recorded press can be decided again under every rule, and
switching rules is one constant, `MergeRule.shipped`.

**The decision deadline is a safety bound, not the latency target.** The operator accepts up to
0.5 s from the end of a press to its outcome. That 0.5 s is the target, to be measured on every
press. A press waits for its Recording Transcript at most 1.5 s after it ends, then takes the Live
Transcript's outcome. The Mac decodes a clip in 318 ms at p90,
and the iPhone is unmeasured, so a 0.5 s bound could hand most presses back to the 44% engine
without anyone seeing it happen. The code that waits keeps both numbers as named constants in one
place.

**The model is downloaded, never bundled.** `openai_whisper-small.en` is 465 MB. The app downloads
the model and its tokenizer at pinned revisions into Application Support, excluded from backup, and
only on a network that is neither expensive nor constrained. A download the network cuts off stops
and resumes later. Core ML specializes the model once after each download and each OS update, which
took 35 to 417 s on the Mac. The model is not loaded at launch. The first press that finds it out of
memory starts loading it, so that press usually misses and the next one reads with it. It leaves
memory on a memory warning, after 30 minutes with no press, and when the phone runs critically hot.
`SpeechModelPlan` in `Sources` decides each of those steps as a table the tests pin, and
`WhisperEngine` in the App carries them out, all off the main actor. No press calls WhisperKit
unless the model is ready, because WhisperKit would otherwise load it inside the press. On a phone
the model runs on the CPU and the Neural Engine, never the GPU, which iOS refuses an app in the
background. Until the model is ready, the Live Transcript decides every press, and Settings shows
where the model stands.

No Simulator loads or downloads the model by default, because parallel lanes run many simulators
and fixtures hear canned transcripts from both engines. A DEBUG fixture launch reads a model from a
host path and a WAV file as the press's recording to prove real decoding in the app, and it is off
by default. A Simulator has no Neural Engine, so there the model runs on the GPU and decodes a
two-second clip in about 2.7 s. That launch may therefore set a longer Decision Deadline. No shipped
path changes it. WhisperKit is a dependency of the App target only, so `swift test` and the CLI
never compile it, and a lint rule keeps its import to `WhisperEngine`.

**Considered alternatives:**
- *Whisper alone, with its own voice-activity detection for the auto-stop:* the card loses its live
  caption, and the auto-stop moves to an energy threshold that plates and gym music may defeat,
  which nobody has measured. A phone without the model, or an App Intent's cold launch, would have
  no speech at all, where the two engines fall back to SpeechAnalyzer.
- *A journal of press events reduced into an outcome:* it rewrites `SetDictation` and its test fakes
  further than anything else considered, before any accuracy ships. Its metrics, a per-press check
  against the latency target and the cause of each wait, carry over to the dictation records.
- *One candidate list, the Recording Transcript first and the Live Transcript after it:* the
  smallest diff, but SpeechAnalyzer's alternatives would settle values Whisper cut off, which
  changes the Spoken Set rule. The list also loses which engine said what, so `gate` could not be
  written.
