#!/bin/bash
# Measures how often real speech writes the Set the athlete meant. Every corpus phrase is spoken by
# macOS `say` in each voice at each rate, heard by `workout hear` through the speech model the
# app's mic uses, and written under the Dictation write policy on a card whose pre-fill differs
# from the intent, so an unsaid value can never pass as heard.
#
# Each sample lands in one class:
#   CORRECT  wrote exactly the intent (a REJECT, SKIP, or SAME row: did what the row asks)
#   WRONG    wrote anything else, including any write for a REJECT row
#   NOWRITE  rejected, missing values, or nothing heard, where a write was meant
#
# --paced plays each phrase at the pace it was spoken, as the mic hears a press, after 0.5 s of
# silence and before 4 s more of it, the athlete still holding. Each sample then records its
# caption lag: how long after the phrase began the card's first caption arrived.
#
# Usage: scripts/measure-dictation.sh [--voices "A,B"] [--rates "160,200,240"] [--corpus FILE]
#                                     [--jobs N] [--out DIR] [--audio-cache DIR] [--paced]
#        scripts/measure-dictation.sh summarize RESULTS.tsv
#
# The corpus is a TSV of `phrase<TAB>intent`. An intent is `weight|reps|rpe`, where `*` means
# the card's pre-fill is the value meant and BW is bodyweight, or SKIP, SAME, or REJECT. Audio is
# cached per (voice, rate, phrase), so a rerun pays only for `hear`. Set WORKOUT_BIN to skip the
# build and use that `workout`. macOS 26 or later.

set -euo pipefail

default_voices="Samantha,Daniel,Karen,Moira,Rishi,Aman,Tara,Tessa,Kathy,Fred,Ralph,Albert,\
Eddy (English (US)),Eddy (English (UK)),Flo (English (US)),Flo (English (UK)),\
Reed (English (US)),Reed (English (UK)),Rocko (English (US)),Rocko (English (UK)),\
Sandy (English (US)),Sandy (English (UK)),Shelley (English (US)),Shelley (English (UK))"
default_rates="160,200,240"
# The Set Log `workout log` writes before a SAME row, which the row's card then repeats.
same_source="200x6@9"
same_source_card="w1d1.e0.s0"
same_card="w1d1.e0.s1"
# Tried in order for every other row: the first whose pre-fill clashes with no field of the intent.
cards=(w1d1.e0.s0 w1d1.e1.s0 w1d2.e1.s0 w1d2.e0.s0)
header=$'voice\trate\tphrase\tintent\tcard\tprefill\texpected\toutcome\tdetail\twritten\tclass\theard\tcandidates\tcaption_lag_ms'
# The silence a paced phrase is spoken between, in milliseconds.
paced_lead=500
paced_tail=4000

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

# The card's pre-fill as `weight|reps|rpe`, `-` for a value the card leaves empty, read as
# SetLogDraft(prefilling:) reads the Set.
prefills() {
    { workout session w1d1 && workout session w1d2; } | jq -r '
    .exercises[].sets[] | select(.state == "pending")
    | [.id,
       (if .loadSuggestion.kind == "bodyweight" then "BW"
        elif .loadSuggestion.weight then (.loadSuggestion.weight | tostring) else "-" end),
       (.prescribedReps | if test("^[0-9]+$") then . else "-" end),
       (.prescribedLoad | capture("^RPE\\s*(?<rpe>.+)$")?.rpe // "-")]
    | "\(.[0])\t\(.[1])|\(.[2])|\(.[3])"'
}

# A clash is a said value equal to the pre-fill, or a `*` where the card pre-fills nothing.
pick_card() {
    local intent=$1 table=$2 card
    for card in "${cards[@]}"; do
        local prefill
        prefill=$(awk -F'\t' -v c="$card" '$1 == c { print $2 }' <<<"$table")
        [ -n "$prefill" ] || continue
        case $intent in
            SKIP | REJECT) printf '%s\t%s\n' "$card" "$prefill"; return 0 ;;
        esac
        if awk -F'|' -v i="$intent" 'BEGIN { split(i, want, "|") }
            { for (f = 1; f <= 3; f++) { if (want[f] == "*" && $f == "-") exit 1; if (want[f] != "*" && want[f] == $f) exit 1 } }' <<<"$prefill"
        then printf '%s\t%s\n' "$card" "$prefill"; return 0; fi
    done
    return 1
}

sample() {
    local out=$1 voice=$2 rate=$3 phrase=$4 intent=$5
    local key voice_dir audio home table card prefill expected report spoken=$phrase
    [ -z "${paced:-}" ] || spoken="[[slnc $paced_lead]] $phrase [[slnc $paced_tail]]"
    key=$(printf '%s' "$spoken" | md5 -q)
    voice_dir=$audio_cache/$(printf '%s' "$voice" | tr -c 'A-Za-z0-9_' '_')/$rate
    audio=$voice_dir/$key.aiff
    if [ ! -s "$audio" ]; then
        mkdir -p "$voice_dir"
        say -v "$voice" -r "$rate" -o "$audio.$$.tmp" "$spoken"
        mv "$audio.$$.tmp" "$audio"
    fi
    home=$(mktemp -d)
    export WORKOUT_HOME=$home
    workout init --scenario fresh-block >/dev/null
    if [ "$intent" = SAME ]; then
        workout log "$same_source_card" "$same_source" >/dev/null
        card=$same_card
        prefill=$(prefills | awk -F'\t' -v c="$card" '$1 == c { print $2 }')
        expected=$same_source
    else
        table=$(prefills)
        if ! IFS=$'\t' read -r card prefill < <(pick_card "$intent" "$table"); then
            printf 'no card fits "%s" (%s): every pre-fill clashes\n%s\n' "$phrase" "$intent" "$table" >&2
            rm -rf "$home"
            exit 1
        fi
        case $intent in
            SKIP | REJECT) expected=$intent ;;
            *) expected=$(awk -F'|' -v i="$intent" 'BEGIN { split(i, want, "|") }
                { for (f = 1; f <= 3; f++) if (want[f] == "*") want[f] = $f; printf "%sx%s@%s\n", want[1], want[2], want[3] }' <<<"$prefill") ;;
        esac
    fi
    # A hear that never returns (one in 5,328 did, on macOS 27) would otherwise hold the whole run.
    report=$(perl -e 'alarm shift; exec @ARGV' "${MEASURE_DICTATION_HEAR_SECONDS:-60}" workout hear "$card" "$audio" ${paced:+--paced} 2>/dev/null) && status=0 || status=$?
    rm -rf "$home"
    if [ "$status" = 142 ]; then
        report='{"heard":"","candidates":[],"outcome":"timed out"}'
    elif [ -z "$report" ]; then
        report='{"heard":"","candidates":[],"outcome":"no report"}'
    fi
    jq -r --arg voice "$voice" --arg rate "$rate" --arg phrase "$phrase" --arg intent "$intent" \
        --arg card "$card" --arg prefill "$prefill" --arg expected "$expected" --argjson lead "$paced_lead" '
        def clean: tostring | gsub("[\t\n]"; " ");
        (if .outcome == "logged" then .setLog elif .outcome == "skipped" then "SKIP" else "-" end) as $written
        | (if .rejection then .rejection.reason + (if .rejection.field then " " + .rejection.field else "" end)
           elif .missing then (.missing | join(",")) else "-" end) as $detail
        | (if $written == "-" then (if $expected == "REJECT" then "CORRECT" else "NOWRITE" end)
           elif $written == $expected then "CORRECT" else "WRONG" end) as $class
        | [$voice, $rate, $phrase, $intent, $card, $prefill, $expected, .outcome, $detail, $written, $class,
           (.heard | clean), (.candidates | map(clean) | join(" | ")),
           ([.captions[]? | select(.heard != "")][0].atMs | if . then . - $lead else "-" end)] | @tsv' <<<"$report" \
        >"$out/samples/$(printf '%s\t%s\t%s' "$voice" "$rate" "$phrase" | md5 -q).tsv"
}

summarize() {
    local results=$1
    awk -F'\t' '
    NR == 1 { next }
    {
        n++; class[$11]++; voice[$1]++; vc[$1, $11]++; rate[$2]++; rc[$2, $11]++
        if ($4 != "REJECT" && $4 != "SKIP" && $4 != "SAME") { writable++; wclass[$11]++ }
        if ($11 == "WRONG") wrong[++nw] = $0
        if ($14 ~ /^-?[0-9]+$/) lag[++nl] = $14 + 0
        if ($11 == "NOWRITE") {
            cause = $8 " (" $9 ")"; causes[cause]++
            key = $3 " | " cause; byphrase[key]++
            heards[key] = (heards[key] == "" ? "" : heards[key] "; ") "\"" $12 "\""
        }
    }
    function pct(a, b) { return b ? sprintf("%5.1f%%", 100 * a / b) : "    -" }
    END {
        printf "samples %d: CORRECT %d (%s)  WRONG %d  NOWRITE %d\n", n, class["CORRECT"], pct(class["CORRECT"], n), class["WRONG"], class["NOWRITE"]
        printf "rows meant to write (%d samples): CORRECT %d (%s)  WRONG %d  NOWRITE %d\n\n", writable, wclass["CORRECT"], pct(wclass["CORRECT"], writable), wclass["WRONG"], wclass["NOWRITE"]
        if (nl) {
            for (i = 2; i <= nl; i++) { v = lag[i]; for (j = i - 1; j > 0 && lag[j] > v; j--) lag[j + 1] = lag[j]; lag[j + 1] = v }
            printf "caption lag (%d samples): p50 %d ms  p90 %d ms  max %d ms\n\n", nl, lag[int((nl + 1) / 2)], lag[int(nl * 0.9 + 0.5) > 0 ? int(nl * 0.9 + 0.5) : 1], lag[nl]
        }
        printf "%-22s %7s %7s %7s %8s\n", "voice", "CORRECT", "WRONG", "NOWRITE", "correct"
        for (v in voice) printf "%-22s %7d %7d %7d %8s\n", v, vc[v, "CORRECT"], vc[v, "WRONG"], vc[v, "NOWRITE"], pct(vc[v, "CORRECT"], voice[v]) | "sort"
        close("sort")
        printf "\n%-22s %7s %7s %7s %8s\n", "rate", "CORRECT", "WRONG", "NOWRITE", "correct"
        for (r in rate) printf "%-22s %7d %7d %7d %8s\n", r, rc[r, "CORRECT"], rc[r, "WRONG"], rc[r, "NOWRITE"], pct(rc[r, "CORRECT"], rate[r]) | "sort -n"
        close("sort -n")
        printf "\nWRONG (%d):\n", nw
        for (i = 1; i <= nw; i++) print "  " wrong[i]
        printf "\nNOWRITE by cause:\n"
        for (c in causes) printf "%6d  %s\n", causes[c], c | "sort -rn"
        close("sort -rn")
        printf "\nNOWRITE by phrase and cause, with each top transcript:\n"
        for (k in byphrase) printf "%6d  %s  %s\n", byphrase[k], k, heards[k] | "sort -rn"
        close("sort -rn")
    }' "$results"
}

case ${1:-} in
    -h | --help) usage; exit 0 ;;
    summarize) [ $# = 2 ] || { usage >&2; exit 64; }; summarize "$2"; exit 0 ;;
    --sample) shift; audio_cache=$1; shift; sample "$@"; exit 0 ;;
esac

voices=$default_voices rates=$default_rates jobs=6 out="" paced="" audio_cache=${HOME}/Library/Caches/workout-measure-dictation
corpus=$(cd "$(dirname "$0")" && pwd)/dictation-corpus.tsv
while [ $# -gt 0 ]; do
    case $1 in
        --voices) voices=$2 ;;
        --rates) rates=$2 ;;
        --corpus) corpus=$2 ;;
        --jobs) jobs=$2 ;;
        --out) out=$2 ;;
        --audio-cache) audio_cache=$2 ;;
        --paced) paced=1; shift; continue ;;
        *) usage >&2; exit 64 ;;
    esac
    shift 2
done
[ -n "$out" ] || out=/tmp/workout-measure-dictation/$(date +%Y%m%d-%H%M%S)

cd "$(git rev-parse --show-toplevel)"
if [ -n "${WORKOUT_BIN:-}" ]; then
    bin_dir=$(cd "$(dirname "$WORKOUT_BIN")" && pwd)
    export PATH="$bin_dir:$PATH"
else
    swift build --product workout >/dev/null 2>&1
    export PATH="$PWD/.build/debug:$PATH"
fi
command -v workout >/dev/null || { echo "no workout binary on PATH" >&2; exit 3; }

IFS=',' read -r -a voice_list <<<"$voices"
IFS=',' read -r -a rate_list <<<"$rates"
for voice in "${voice_list[@]}"; do
    say -v '?' | grep -q "^$voice " || { echo "voice $voice is not installed; add it in System Settings > Accessibility > Spoken Content" >&2; exit 3; }
done

mkdir -p "$out/samples" "$audio_cache"
jobs_file=$out/jobs.nul
: >"$jobs_file"
count=0
while IFS=$'\t' read -r phrase intent; do
    [ "$phrase" != phrase ] || continue
    [ -n "$phrase" ] || continue
    for voice in "${voice_list[@]}"; do
        for rate in "${rate_list[@]}"; do
            printf '%s\0%s\0%s\0%s\0' "$voice" "$rate" "$phrase" "$intent" >>"$jobs_file"
            count=$((count + 1))
        done
    done
done <"$corpus"
echo "$count samples: ${#voice_list[@]} voices x ${#rate_list[@]} rates x $((count / (${#voice_list[@]} * ${#rate_list[@]}))) phrases, $jobs at a time; results in $out"

export paced
xargs -0 -n 4 -P "$jobs" "$0" --sample "$audio_cache" "$out" <"$jobs_file"

results=$out/results.tsv
{ echo "$header"; cat "$out"/samples/*.tsv | sort -t$'\t' -k3,3 -k1,1 -k2,2n; } >"$results"
rm -rf "$out/samples" "$jobs_file"
written=$(($(wc -l <"$results") - 1))
[ "$written" = "$count" ] || { echo "only $written of $count samples reported" >&2; exit 1; }
summarize "$results" | tee "$out/summary.txt"
echo
echo "results: $results"
