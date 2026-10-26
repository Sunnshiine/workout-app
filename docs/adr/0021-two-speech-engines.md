# Two speech engines decide a Dictation

Dictation hears the athlete through SpeechTranscriber, the SpeechAnalyzer model. On the speech
bench, prompted Whisper small (WhisperKit, `openai_whisper-small.en` with prompt p1) wrote the
correct Set for 89.4% of 2,832 held-out clips, and SpeechTranscriber for 44.0%. The bench ran on an
M-series Mac with synthetic `say` voices. No iPhone has been measured. Whisper reads a recording in
one batch after the athlete stops, and it emits nothing while they speak. Two things need words as
they arrive. Hands-free listening stops 1.2 s after the caption last changed, and the card captions
the press as the athlete speaks. Whisper alone would break both.

**Amended 2026-10-26:** hands-free listening now stops at a Pause the mic level hears and
Whisper confirms. SpeechTranscriber releases captions in blocks of about 3.9 s of audio, so a stop
1.2 s after the caption last changed landed about 3.6 s after the athlete stopped talking. The
recorder now keeps a level for each 85 ms frame of the press's recording, one 4096-frame tap buffer
at 48 kHz. The noise floor is the 15th percentile of the levels so far. A frame 9 dB over it is
loud, and two loud frames in a row are speech. The quiet frames since the last loud one are the
Pause (CONTEXT.md). At a 341 ms Pause, Whisper reads the recording so far. When that transcript
names the whole Set by itself and writes under the single-engine policy, listening stops. A whole
RPE under 10 waits for a 1024 ms Pause instead, because "and a half" may follow. Otherwise a 1.2 s
Pause stops listening, beside the caption's 1.2 s silence window and the 8 s cap. A stop decides
with that early read when the athlete said nothing after it, so Whisper reads the press once. A
held press the athlete releases is unchanged. Each Dictation Record names when its early read was
asked and when the read it was decided with was asked.

This contradicts the first considered alternative below, which set an energy threshold aside as
something plates and gym music may defeat, unmeasured. A throwaway prototype measured the rule on 77
corpus phrases and 10 phrases with a 600 to 700 ms gap inside them. One synthetic `say` voice spoke
each phrase, Samantha at 200 words a minute. Each clip ran clean and with stationary pink noise at
15 dB SNR, and Whisper read it on an M-series Mac's Neural Engine. On the clean corpus, speech end
to logged fell from 3071 ms to 1272 ms at p50 and from 3810 ms to 1638 ms at p90, with every outcome
the same as before. A 683 ms wait for a half wrote two wrong Set Logs on the noisy gap phrases,
225x3@8 for "at 8 … and a half" and 225x3@9 for "at 9 … point 5", and a 512 ms wait wrote those two
clean as well. The margin was swept only at the 683 ms and 512 ms waits. Against 9 dB there, a 12 dB
margin heard nothing in one more noisy corpus phrase and, at 512 ms, wrote three wrong Set Logs on
the corpus, one clean and two noisy. A 6 dB margin changed no outcome. 9 dB was kept because a lower
margin hears more noise as speech, which stationary noise did not test. The rule ships the 9 dB
margin and the 1024 ms wait for a half, and neither 6 nor 12 dB was run at 1024 ms. Nobody has
measured plate clanks, gym music, a real athlete's voice, the phone's own mic, or how fast an iPhone
decodes. Noise the level hears as speech delays the stop, or sends the next Pause to a new read.
Speech the level hears as quiet, as a half said under music, could stop listening on the read before
it, and how often that happens is unknown. Recorded presses can now measure it.

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
  no speech at all, where the two engines fall back to SpeechAnalyzer. The 2026-10-26 amendment
  above measured that threshold, on synthetic voices only, and keeps the caption beside it.
- *A journal of press events reduced into an outcome:* it rewrites `SetDictation` and its test fakes
  further than anything else considered, before any accuracy ships. Its metrics, a per-press check
  against the latency target and the cause of each wait, carry over to the dictation records.
- *One candidate list, the Recording Transcript first and the Live Transcript after it:* the
  smallest diff, but SpeechAnalyzer's alternatives would settle values Whisper cut off, which
  changes the Spoken Set rule. The list also loses which engine said what, so `gate` could not be
  written.
