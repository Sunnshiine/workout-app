#!/usr/bin/env bash
# Fail on a workflow `if:` that reads a step result and calls no status check function.
#
# GitHub prepends `success() &&` to an `if:` that calls none of `success()`, `failure()`, `always()`,
# or `cancelled()`. A guard on `steps.<id>.conclusion` or `steps.<id>.outcome` without one is then
# false once any earlier step fails, whatever it appears to say. #606 shipped that shape: a guard that
# read as "run after the gate, pass or fail" skipped on every red run, and review could not see it
# (issue #643). The YAML is read by indentation rather than parsed, because a finding needs its line
# number and the check has to run with nothing but bash and awk.
#
#   scripts/lint-workflow-ifs.sh           check .github/workflows/*.yml and *.yaml (what CI runs)
#   scripts/lint-workflow-ifs.sh FILE...   check the named files
set -euo pipefail

if [ "$#" -eq 0 ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$ROOT"
    shopt -s nullglob
    set -- .github/workflows/*.yml .github/workflows/*.yaml
    if [ "$#" -eq 0 ]; then
        echo "error: $ROOT/.github/workflows holds no .yml or .yaml file, so this run would check nothing." >&2
        exit 2
    fi
fi
for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "error: $file does not exist." >&2
        exit 2
    fi
done

awk -v sq="'" '
BEGIN { BLOCK = "[|>]([-+][1-9]?|[1-9][-+]?)?[ \t]*(#.*)?$" }

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }

function scalar(v) {
    v = trim(v)
    if (match(v, /^"[^"]*"/) || match(v, "^" sq "[^" sq "]*" sq)) return substr(v, 2, RLENGTH - 2)
    sub(/[ \t]+#.*$/, "", v)
    return v
}

function label(u) { return sname[u] != "" ? sname[u] : (sid[u] != "" ? sid[u] : "#" spos[u]) }

function finish_if() {
    collecting = 0
    if (cond !~ /steps\.[A-Za-z0-9_-]+\.(conclusion|outcome)/) return
    if (index(cond, "success(") || index(cond, "failure(") || index(cond, "always(") || index(cond, "cancelled(")) return
    n++
    fpath[n] = if_path; fline[n] = if_line; fjob[n] = if_job; fstep[n] = if_step; fcond[n] = cond
}

FNR == 1 {
    if (collecting) finish_if()
    skip = -1; injobs = 0; job = ""; jcol = -1; jkcol = -1; scol = -1; step = 0
}

{
    c = $0
    sub(/^[ \t]+/, "", c)
    ind = length($0) - length(c)
    blank = (c == "")
}

collecting {
    if (blank || ind > if_col) {
        if (!blank) cond = cond (cond == "" ? "" : " ") trim(c)
        next
    }
    finish_if()
}

skip >= 0 {
    if (blank || ind > skip) next
    skip = -1
}

blank || c ~ /^#/ { next }

{
    k = c; kcol = ind
    if (c ~ /^-[ \t]/) { match(c, /^-[ \t]+/); kcol = ind + RLENGTH; k = substr(c, RLENGTH + 1) }

    if (ind == 0) {
        injobs = (c ~ /^jobs:/); job = ""; jcol = -1; scol = -1; step = 0
    } else if (injobs) {
        if (jcol < 0) jcol = ind
        if (ind <= jcol) {
            job = c; sub(/:.*/, "", job); jkcol = -1; scol = -1; step = 0; nstep = 0
        } else {
            if (jkcol < 0) jkcol = ind
            # Step items may sit at the same column as steps: itself, so only a non-item line there ends it.
            if (scol >= 0 && (ind < scol || (ind == scol && c !~ /^-/))) { scol = -1; step = 0 }
            if (ind == jkcol && k ~ /^steps:/) {
                scol = ind; icol = -1
            } else if (scol >= 0 && (c == "-" || c ~ /^-[ \t]/) && (icol < 0 || ind == icol)) {
                icol = ind; step = ++uid; spos[step] = ++nstep; skcol = kcol
            }
        }
    }

    if (k ~ /^if:/) {
        total++; collecting = 1
        if_col = kcol; if_line = FNR; if_path = FILENAME; if_job = job; if_step = step
        cond = k
        sub(/^if:[ \t]*/, "", cond)
        if (cond ~ "^" BLOCK) cond = ""
        else { sub(/[ \t]+#.*$/, "", cond); cond = trim(cond) }
        next
    }
    if (step && kcol == skcol) {
        if (k ~ /^name:/) sname[step] = scalar(substr(k, 6))
        else if (k ~ /^id:/) sid[step] = scalar(substr(k, 4))
    }
    if (k ~ "^[^ \t#][^:]*:[ \t]+" BLOCK) skip = kcol
}

# Findings print here, not as found, because a step name: can follow its if:.
END {
    if (collecting) finish_if()
    for (i = 1; i <= n; i++) {
        where = "job " sq fjob[i] sq
        if (fstep[i]) where = where ", step " sq label(fstep[i]) sq
        print fpath[i] ":" fline[i] ": " where ": if: reads a step conclusion or outcome and calls no status check function"
        print "    " fcond[i]
    }
    if (n) {
        print "GitHub prepends success() && to an if: that calls no status check function, so these guards are"
        print "false once an earlier step fails. Start one with !cancelled() && to run after a failure, or with"
        print "success() && if \"the job is green so far\" is what it means."
        exit 1
    }
    print "==> Clean: " (total + 0) " if: conditions in " (ARGC - 1) " file(s)"
}
' "$@"
