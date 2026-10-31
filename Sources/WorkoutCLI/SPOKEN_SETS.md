# Spoken Sets in the workout CLI

How `say`, `hear`, and their recordings read a Spoken Set. The rest of the CLI is in
[README.md](README.md).

## Spoken Sets

`say` reads a transcript as a Spoken Set and does what the Set card would do with it. Each value
said replaces the one the card pre-fills (the Set's own Set Log, else `loadSuggestion` and the
prescribed reps and RPE), and the rest keep the pre-fill. A weight or reps the athlete did not say
and the card does not hold is never guessed.

On the facade, `say` is `dictate(_ candidates: [String], at:)` with one transcript. `dictate` takes
a recognizer's transcripts, most likely first, under the Dictation write policy: only the most
likely transcript writes. A Set only the less likely ones read, and agree on, is `rejected` as
`ambiguous` with nothing written. The headless Dictation the Action button and Control Center run
on a locked phone writes through the same call.

| `outcome` | Means | Carries | Exit |
|---|---|---|---|
| `logged` | weight, reps, and RPE are all present, logged through `WorkoutStore.log` | `setLog` | 0 |
| `skipped` | "skip", "skip it", "skip set", "skip this set", or "skipped", through `WorkoutStore.skip` | | 0 |
| `missingValues` | a value is still missing, so nothing is queued and the Set stays Pending | `missing`: `weight`, `reps`, `rpe` | 0 |
| `rejected` | the transcript is not a Set, so nothing is queued | `rejection`: `reason`, and `field` or `value` | 1 |

`rejection.reason` is `nothingHeard`, `unrecognized`, `kilograms`, `fusedNumber` (numbers the
recognizer ran together), `ambiguous` (a number no word places, or words that may mean another Set),
`conflicting` (a `field` said twice, even as the same number, which reads as two Sets),
`outOfRange` (reps that are 0 or not whole, or a weight of 0 pounds), `implausible` (a `field` no
lifter logs, more likely misheard than said: more than 100 reps, or a weight that is not a multiple
of 0.25 pounds), `offLadderRPE` (the `value` heard is not an RPE), or `nothingToRepeat` ("same
again" with no earlier Set Log of the Exercise in the Session). A Dictation that listened, rather than read a
transcript, may also be `microphoneDenied`, `speechUnavailable`, or `listeningFailed`. A rejected
`say` prints its report, then a `spoken_set_rejected` error.

The grammar, as the `SpokenSetTests` files in `Tests/Unit/` pin it. A number is a value only
where a word next to it, or the phrase around it, says which, never by its place in the transcript.

- "for", "x", "by", and "times" put the weight before them and the reps after them ("185 for 5"),
  and said first they label the reps ("for 5"). "four" between a weight and a number is "for" too
  ("185 four 5"), and so is "per" after bodyweight or a weight heavier than the reps
  ("95 pounds per 6"). "25 per 30" is `ambiguous`. "or" between numbers is always `ambiguous`:
  "225 or 3" may be "225 for 3", and "20 or 25 reps" is a range.
- "pounds", "pound", "lbs", and "lb" label the number before them as the weight, as "£" does the
  number after it, even after "at" ("12 reps at 10 pounds"). "reps" labels the number before or
  after it ("8 reps", "reps 8"), as do the "rebs", "ribs", "rips", and "representatives" the
  recognizer writes for it. "with" labels bodyweight or a number off the RPE ladder after it
  as the weight, "pounds" after it or not ("5 reps with 185 pounds"), and is filler anywhere else,
  so "for 5 with 8" is `ambiguous`.
- "RPE", "rp", "r p e", "RTE", "RTD", "RTV", "RPA", "RPD", "PE", "our fee", "felt like", and "@"
  label the number after them as the RPE, and "RPE" labels the number before it too ("8 RPE"). After "at", a number on the RPE ladder is the RPE
  ("at 8"), and bodyweight or any other number is the weight ("8 reps at 12").
- Right after a whole weight for reps, "and", "of", "add", or "to" before a number is the "at" the
  recognizer mishears, and the number after it is never read: "185 for 5 and 8" and "225 for 3 to
  8" are `missingValues` with the RPE missing, because "185 for 5 and 5" may be five Sets of five.
  Only an "RPE" said last labels it: "135 for 8 and 9 RPE" logs 135x8@9. `hear` and the mic
  fill a value the top transcript cut off from the alternative transcripts, when every one that
  hears the same weight and reps hears the same RPE and it is the number the top wrote in its
  place: "185 for 5 and 8" beside "185 for 5 at 8" logs 185x5@8, and beside "185 for 5 at 7", or
  beside "185 for 5 at 8" and "185 for 5 at 9", stays `missingValues`. Where the top wrote no
  number, the alternatives supply it: "185 for 5 at" beside "185 for 5 at 8" logs 185x5@8.
- An alternative that is the top transcript with words before it heard the start the top cut off,
  and stands in for the top when every such alternative that reads agrees: "for 12 at 8" beside "10
  for 12 at 8" logs 10x12@8 rather than the card's weight, and "reps at 135" beside "8 reps at 135"
  logs 135x8. Two that restore it differently, as "10 for 12 at 8" and "20 for 12 at 8", are
  `ambiguous`. An alternative whose first number is longer than the top's and ends in it may have
  heard the start the top lost, so "25 for 3 add 8" beside "225 for 3 add 8" is `ambiguous`.
- Where the top has a number no word places, an alternative that is the top with only "at" added
  heard the "at" the top lost, and stands in for the top when every such alternative that reads
  agrees: "275 for 4 9" beside "275 for 4 at 9" logs 275x4@9. Any other word added leaves it a
  guess, because "135 for 49 reps" beside "135 for 49" would read reps where "4 at 9" was said.
- A transcript that ends on "and", "and a", or "point" right after a number had its half or decimal
  cut off, so that value is missing: "at 8 and a" is `missingValues` with the RPE missing, and only
  an alternative that hears 8 and a half settles it. A rep count is whole, so after one it is the
  RPE that is missing ("185 for 5 and").
- A value said twice is `conflicting`, even as the same number: "185 for 5 for 5" and "185 for 5
  reps, 5 reps".
- A Spoken Set holds any weight and rep count a lifter logs: "4 for 5", "5 by 5", "135 for 45",
  "135 for 100 reps", and "182.25 for 3" each read as said. Reps that are 0 or not whole, or a
  weight of 0 pounds, is `outOfRange` ("135 for 0", "315 for 19.5", "0 for 5"), because a Set with
  no load is bodyweight and a Set not done is Skipped. More than 100 reps, or a weight that is not a
  multiple of 0.25 pounds, is `implausible` ("135 for 101 at 8", "12.47 for 3", which the recognizer
  writes for "1247"), though the card takes either typed, because a value no lifter logs is more
  likely misheard than said.
- A number no word places is `ambiguous`, never filled into a free value: "185, 5, 8", "5 at 8",
  "for 5, 8", and "eight" alone. The one exception is a number that leads the transcript when words
  label both the reps and the RPE after it: "135, 8 reps, RPE 9" logs 135x8@9, because the recognizer
  writes that "for" as a comma, and the weight is the only value left. "8 reps, RPE 9, 135" stays
  `ambiguous`. A leading number that ends in 4 is `fusedNumber` instead, because "eighty for"
  sounds as "eighty-four": the recognizer writes "80 for 5 reps at 8" as "84 5 reps at 8" and "180
  for 5 reps at 8" as "184 5 reps at eight". "84 for 5" logs as said.
- Number words read as athletes say them: "one thirty five", "four oh five", "hundred eighty five",
  "one thousand", "a thousand and five", "one thousand five hundred", "eleven hundred", "ten fifty",
  "eight and a half", "8 1/2", "8½", "one eighty seven point five", a clock-style "1:35" for 135,
  and "1,005", where a comma before exactly three digits separates thousands ("135,8" stays 135 and 8).
  "ate" and "age" are 8, "single", "double", and "triple" are 1, 2, and 3 reps ("225 for a
  triple at 8") and never part of a number word ("one eighty single for 5" is `ambiguous`), and
  "to" or "too" is 2 only where a number is asked for. Number words in a row that
  make no one number, as "nine five", are `ambiguous`. A tens word and a unit after it are always
  one number, so "forty four five" is 44 and an unplaced 5, `ambiguous`.
- A number of 1,000 or more, in digits or words, is the weight only where it cannot hide another
  value: "for", "x", or "by" follows it and words label the reps and the RPE, as in "1005 for 1 at
  10", or "pounds" or "lb" follows it and words label the reps, as in "1005 pounds for 1". Anywhere
  else it is `fusedNumber`, because "1358" may be "135 for 8", "ten fifty" "10 for 50", "40542"
  "four oh five for two", and the 4 of "1854 5 reps at RPE 8" the "for" of "185 for 5": "1358",
  "1358 at 9", "40542 at nine", "1000 for 5", "1000, 5 reps, RPE 8", "ten fifty", and "135 for
  1000 at 8" are rejected. The weight has no upper bound, as on the card.
- A rep count right after "for", with no "reps" after it and no RPE said, is `ambiguous` as two
  digits whose second is 6 to 9, and as 100 in digits or words: "135 for 19" may be "135 for 1 at
  9", and "135 for one hundred" is `ambiguous` too. More than 100 reps is `implausible` wherever it
  sits, as "135 for 808", which the recognizer writes for "135 for 8 at an 8". "135 for 19 reps",
  "135 for 100 reps", "135 for 15", and "45 for 10" log.
- "a" right after a number, or between "for" and a number, keeps the number from the label across
  it, so "135, a representative, RP9", the recognizer dropping the 8 of "135, 8 reps, RPE 9", and
  "135 for a 9", the recognizer's "a" for the "8 at" of "135 for 8 at 9", are `unrecognized`. "225
  for a triple at 8", "135 for a hundred reps", and "225 for 3 at a 9" read as said.
- "bodyweight", "body weight", and "BW" are the BW weight, as are the "body waits" and "Bobby waits"
  the recognizer writes for it.
- "same again", "same", "same as last", "same as before", "do the same", "repeat", and "again" log
  the Exercise's nearest earlier Set Log in the Session. A command acts on this Set alone, so one
  that names a Set or Session, as "skip set one", "same as set one", and "same as last time" do, is
  `ambiguous`. Any other word in a command, as "same weight", is `unrecognized`.
- Filler such as "um", "okay", "please", "thanks", "yeah", "I", "just", "hit", "did", and "got" is
  dropped. Any other word, or a symbol such as "%", "+", or the minus of "135 for -5", rejects the
  transcript rather than being skipped.

```console
$ workout say w1d1.e0.s0 "RPE 9" | jq -c '{outcome, missing}'
{"outcome":"missingValues","missing":["weight"]}
$ workout say w1d1.e0.s0 "185 for 5 at 8" | jq -c '{outcome, setLog}'
{"outcome":"logged","setLog":"185x5@8"}
$ workout say w1d1.e0.s1 "at 9" | jq -c '{outcome, setLog}'     # the card's estimate, at the RPE said
{"outcome":"logged","setLog":"180x5@9"}
```

## Recordings

`hear` is `say` with Apple's on-device speech-to-text in front of it. It reads an audio file
through the model, configuration, and transcript mapping the Active Set Card's mic uses
(`Sources/WorkoutTracker/Session/OnDeviceSpeech.swift`): SpeechTranscriber with alternatives for
en-US, or DictationTranscriber where the Mac has no SpeechTranscriber. Then it hands every
transcript, most likely first, to `dictate`, which writes under the same Dictation write policy
as the locked phone. `candidates` is that list; `heard` is its first entry.

```console
$ say -o set.aiff "185 for 5 at 8"
$ workout hear w1d1.e0.s0 set.aiff | jq -c '{candidates, outcome, setLog}'
{"candidates":["185 for 5 at 8.","185 for five at 8.","185 for 5 and 8.","185 for 5 at eight."],"outcome":"logged","setLog":"185x5@8"}
```

It needs macOS 26 or later on a Mac that runs SpeechAnalyzer. The first run downloads the en-US
speech assets from Apple, free and with no account, and prints each whole percent to stderr as
`{"installingSpeechAssets":{"percent":42}}`. A recording with no speech in it is `rejected` as
`nothingHeard`. A path that is not an audio file is `unreadable_recording` (exit 1), a model that
fails partway through is `listening_failed` (exit 3), and a Mac without the model, or whose assets
would not install, is `speech_unavailable` (exit 69). `scripts/prove-dictation.sh` speaks a table
of phrases in two macOS voices, runs each through `hear`, flushes, and prints what landed in the
Sheet. `scripts/measure-dictation.sh` speaks every phrase of `scripts/dictation-corpus.tsv` in
every real English voice at three rates, runs each through `hear` on a card whose pre-fill differs
from the phrase's intent, and counts how many wrote the Set meant (CORRECT), wrote another
(WRONG), or wrote nothing (NOWRITE), by voice, by rate, and by cause. Its results TSV keeps every
transcript the model heard.
