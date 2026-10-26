#!/bin/bash
# shellcheck disable=SC2016  # stubs hold literal $
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -rf "$root"' EXIT
export PATH="$root/bin:$PATH" WORKOUT_BIN=$root/bin/workout STUB_CALLS=$root/calls
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}
expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want the line:\n%s\n' "$2" "$3"; fi
}

mkdir -p "$root/bin"
# The stub records the phrase as the recording, so the stub `workout hear` can read it back.
cat >"$root/bin/say" <<'STUB'
#!/bin/bash
echo "say $*" >>"$STUB_CALLS"
if [ "$1" = -v ] && [ "$2" = '?' ]; then echo "Samantha (English (US)) en_US    # Hello! My name is Samantha."; exit 0; fi
while [ $# -gt 1 ]; do case $1 in -o) out=$2 ;; esac; shift; done
printf '%s' "$1" >"$out"
STUB
cat >"$root/bin/workout" <<'STUB'
#!/bin/bash
echo "workout $*" >>"$STUB_CALLS"
card() { printf '{"id":"%s","state":"pending","prescribedReps":"%s","prescribedLoad":"%s","loadSuggestion":{"kind":"%s"}}' "$@"; }
case $1 in
    init | log) echo '{}' ;;
    session)
        case $2 in
            w1d1) echo "{\"exercises\":[{\"sets\":[$(card w1d1.e0.s0 5 RPE7 none),$(card w1d1.e0.s1 5 RPE7 none)]},{\"sets\":[$(card w1d1.e1.s0 8 RPE8 none)]}]}" ;;
            w1d2) echo "{\"exercises\":[{\"sets\":[$(card w1d2.e0.s0 5 RPE7 none)]},{\"sets\":[$(card w1d2.e1.s0 8 BW bodyweight)]}]}" ;;
        esac ;;
    hear)
        phrase=$(cat "$3")
        case $phrase in
            "185 for 5 at 8") echo '{"heard":"185 for 5 at 8.","candidates":["185 for 5 at 8.","185 for 5 and 8."],"outcome":"logged","setLog":"185x5@8"}' ;;
            "135 for 20") echo '{"heard":"135 for 20.","candidates":["135 for 20."],"outcome":"logged","setLog":"135x20@7"}' ;;
            "225 for 3 for 3") echo '{"heard":"225 for 343.","candidates":["225 for 343.","225 for 3 for 3."],"outcome":"logged","setLog":"225x343@7"}' ;;
            "185 or 5") echo '{"heard":"185 or 5.","candidates":["185 or 5."],"outcome":"rejected","rejection":{"reason":"ambiguous"}}'; exit 1 ;;
            "225 for 3 at 8") echo '{"heard":"225 for 3 add 8.","candidates":["225 for 3 add 8.","225 for 3 at 8."],"outcome":"missingValues","missing":["rpe"]}' ;;
            "same again") echo '{"heard":"Same again.","candidates":["Same again."],"outcome":"logged","setLog":"200x6@9"}' ;;
            "skip") echo '{"heard":"Skip.","candidates":["Skip."],"outcome":"skipped"}' ;;
            "bodyweight for 8") echo '{"heard":"Body weight for 8.","candidates":["Body weight for 8."],"outcome":"logged","setLog":"BWx8@7"}' ;;
            "hangs") sleep 30 ;;
            "[[slnc 500]] 185 for 5 at 8 [[slnc 4000]]")
                [ "$4" = --paced ] || exit 9
                echo '{"heard":"185 for 5 at 8.","candidates":["185 for 5 at 8."],"outcome":"logged","setLog":"185x5@8","captions":[{"atMs":1400,"heard":""},{"atMs":1900,"heard":"185"},{"atMs":2300,"heard":"185 for 5 at 8."}]}' ;;
            "[[slnc 500]] 135 for 20 [[slnc 4000]]")
                echo '{"heard":"135 for 20.","candidates":["135 for 20."],"outcome":"logged","setLog":"135x20@7","captions":[{"atMs":4400,"heard":"135 for 20."}]}' ;;
        esac ;;
esac
STUB
chmod +x "$root/bin/say" "$root/bin/workout"

printf 'phrase\tintent\n%s\n' \
    $'185 for 5 at 8\t185|5|8' $'135 for 20\t135|20|*' $'225 for 3 for 3\tREJECT' $'185 or 5\tREJECT' \
    $'225 for 3 at 8\t225|3|8' $'same again\tSAME' $'skip\tSKIP' $'bodyweight for 8\tBW|8|*' >"$root/corpus.tsv"

: >"$STUB_CALLS"
out=$("$script_dir/../measure-dictation.sh" --voices Samantha --rates 200 --jobs 2 --corpus "$root/corpus.tsv" \
    --out "$root/out" --audio-cache "$root/cache" 2>&1)
status=$?
results=$root/out/results.tsv

echo "the matrix runs every phrase once per voice and rate"
expect "exits 0" "$status" 0
expect "one row per sample" "$(tail -n +2 "$results" | wc -l | tr -d ' ')" 8
expect_line "prints the totals" "$out" "samples 8: CORRECT 6 ( 75.0%)  WRONG 1  NOWRITE 1"
expect_line "prints the totals of the rows meant to write" "$out" "rows meant to write (4 samples): CORRECT 3 ( 75.0%)  WRONG 0  NOWRITE 1"

row() { awk -F'\t' -v p="$1" '$3 == p { print $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9 "\t" $10 "\t" $11 }' "$results"; }
echo "each sample runs on a card whose pre-fill clashes with no field of the intent"
expect "a Set the squat and RDL cards both pre-fill a value of goes to the pull-up card" "$(row '185 for 5 at 8')" $'w1d2.e1.s0\tBW|8|-\t185x5@8\tlogged\t-\t185x5@8\tCORRECT'
expect "a * takes the card's pre-fill" "$(row '135 for 20')" $'w1d1.e0.s0\t-|5|7\t135x20@7\tlogged\t-\t135x20@7\tCORRECT'
expect "BW with 8 reps skips the pull-up card" "$(row 'bodyweight for 8')" $'w1d1.e0.s0\t-|5|7\tBWx8@7\tlogged\t-\tBWx8@7\tCORRECT'
expect "a SAME row repeats the Set Log logged before it" "$(row 'same again')" $'w1d1.e0.s1\t-|5|7\t200x6@9\tlogged\t-\t200x6@9\tCORRECT'
expect_line "the SAME row's home logs the source Set first" "$(cat "$STUB_CALLS")" "workout log w1d1.e0.s0 200x6@9"

echo "each outcome lands in one class"
expect "a REJECT row that writes is WRONG" "$(row '225 for 3 for 3')" $'w1d1.e0.s0\t-|5|7\tREJECT\tlogged\t-\t225x343@7\tWRONG'
expect "a REJECT row that rejects is CORRECT" "$(row '185 or 5')" $'w1d1.e0.s0\t-|5|7\tREJECT\trejected\tambiguous\t-\tCORRECT'
expect "missing values are NOWRITE with the fields missing" "$(row '225 for 3 at 8')" $'w1d1.e0.s0\t-|5|7\t225x3@8\tmissingValues\trpe\t-\tNOWRITE'
expect "a skip is CORRECT" "$(row 'skip')" $'w1d1.e0.s0\t-|5|7\tSKIP\tskipped\t-\tSKIP\tCORRECT'
expect_line "the summary groups NOWRITE by cause" "$out" "     1  missingValues (rpe)"
expect_line "the summary lists each WRONG row" "$out" "  Samantha	200	225 for 3 for 3	REJECT	w1d1.e0.s0	-|5|7	REJECT	logged	-	225x343@7	WRONG	225 for 343.	225 for 343. | 225 for 3 for 3.	-"

echo "a rerun reads the cached audio"
expect "the first run spoke every phrase" "$(grep -c '^say -v Samantha' "$STUB_CALLS")" 8
: >"$STUB_CALLS"
"$script_dir/../measure-dictation.sh" --voices Samantha --rates 200 --jobs 2 --corpus "$root/corpus.tsv" \
    --out "$root/out2" --audio-cache "$root/cache" >/dev/null 2>&1
expect "the second run spoke nothing" "$(grep -c '^say -v Samantha' "$STUB_CALLS")" 0
expect "and reports the same rows" "$(diff "$results" "$root/out2/results.tsv" && echo same)" same

echo "summarize reruns the summary on a saved results file"
expect_line "from the TSV alone" "$("$script_dir/../measure-dictation.sh" summarize "$results")" "samples 8: CORRECT 6 ( 75.0%)  WRONG 1  NOWRITE 1"

echo "a row no card fits stops the run"
printf 'phrase\tintent\n%s\n' $'185 for 8 at 7\t185|8|7' >"$root/clash.tsv"
out=$("$script_dir/../measure-dictation.sh" --voices Samantha --rates 200 --corpus "$root/clash.tsv" --out "$root/out3" --audio-cache "$root/cache" 2>&1)
expect "exits 1" "$?" 1
expect_line "names the row" "$out" 'no card fits "185 for 8 at 7" (185|8|7): every pre-fill clashes'

echo "a hear that never returns is cut off and counted"
printf 'phrase\tintent\n%s\n' $'hangs\t185|5|8' >"$root/hang.tsv"
MEASURE_DICTATION_HEAR_SECONDS=1 "$script_dir/../measure-dictation.sh" --voices Samantha --rates 200 --corpus "$root/hang.tsv" \
    --out "$root/out4" --audio-cache "$root/cache" >/dev/null 2>&1
expect "exits 0" "$?" 0
expect "as a NOWRITE that timed out" "$(awk -F'\t' '$3 == "hangs" { print $8 "\t" $11 }' "$root/out4/results.tsv")" $'timed out\tNOWRITE'

echo "--paced plays each phrase between silences and records its caption lag"
printf 'phrase\tintent\n%s\n' $'185 for 5 at 8\t185|5|8' $'135 for 20\t135|20|*' >"$root/paced.tsv"
out=$("$script_dir/../measure-dictation.sh" --voices Samantha --rates 200 --corpus "$root/paced.tsv" --paced \
    --out "$root/out5" --audio-cache "$root/cache" 2>&1)
expect "exits 0" "$?" 0
expect "the lag runs from the end of the leading silence to the first caption with words" \
    "$(awk -F'\t' '$3 == "185 for 5 at 8" { print $11 "\t" $14 }' "$root/out5/results.tsv")" $'CORRECT\t1400'
expect_line "the summary prints the lag's percentiles" "$out" "caption lag (2 samples): p50 1400 ms  p90 3900 ms  max 3900 ms"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
