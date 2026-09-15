#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-timing.sh [--steps] [--branch NAME --last N] [RUN_ID...]

Prints one row per CI run and the median of each column.

  critical   seconds the slowest job spent executing (started to completed)
  wall       seconds from the first job queued to the last job completed
  runner     executing seconds summed over every job

  --branch NAME --last N   Use the last N successful ci.yml runs on NAME.
  --steps                  Also print every step that took 5 s or longer.
EOF
}

REPO="${CI_TIMING_REPO:-Sunnshiine/workout-app}"
STEPS=0
BRANCH=""
LAST=3
RUNS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --steps) STEPS=1 ;;
        --branch)
            BRANCH="$2"
            shift
            ;;
        --last)
            LAST="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) RUNS+=("$1") ;;
    esac
    shift
done

if [[ -n $BRANCH ]]; then
    while read -r id; do RUNS+=("$id"); done < <(
        gh run list --repo "$REPO" --workflow ci.yml --branch "$BRANCH" --status success \
            --limit "$LAST" --json databaseId --jq '.[].databaseId'
    )
fi

if [[ ${#RUNS[@]} -eq 0 ]]; then
    usage >&2
    exit 2
fi

ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT

printf 'run\tsha\tcritical\twall\trunner\tjobs\n'
for run in "${RUNS[@]}"; do
    sha=$(gh api "repos/$REPO/actions/runs/$run" --jq '.head_sha[0:7]')
    jobs=$(gh api "repos/$REPO/actions/runs/$run/jobs?per_page=100" --jq '.jobs')
    jq -r --arg run "$run" --arg sha "$sha" '
        def secs(a; b): (b | fromdate) - (a | fromdate);
        [.[] | {name, exec: secs(.started_at; .completed_at), created_at, completed_at}] as $j
        | [$run, $sha,
           ($j | map(.exec) | max),
           (($j | map(.completed_at | fromdate) | max) - ($j | map(.created_at | fromdate) | min)),
           ($j | map(.exec) | add),
           ($j | map("\(.name)=\(.exec)") | join(" "))]
        | @tsv' <<<"$jobs" | tee -a "$ROWS"
    if [[ $STEPS -eq 1 ]]; then
        jq -r '.[] | .name as $job | .steps[]
            | select(.completed_at != null)
            | ((.completed_at | fromdate) - (.started_at | fromdate)) as $s
            | select($s >= 5) | "    \($job)\t\($s)s\t\(.name)"' <<<"$jobs"
    fi
done

median() {
    cut -f"$1" "$ROWS" | sort -n | awk '{v[NR] = $1} END {print (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2}'
}
printf 'median\t-\t%s\t%s\t%s\t(n=%s)\n' "$(median 3)" "$(median 4)" "$(median 5)" "$(wc -l <"$ROWS" | tr -d ' ')"
