#!/bin/bash
# One copy of each large, immutable build input for every lane on this Mac (docs/agents/dependency-store.md).
#
# An entry is built in a private staging dir and published with one rename(2), so a reader only
# ever sees a complete entry. A reader never uses the entry in place: it takes an APFS clone
# (cp -c), which shares blocks until written and keeps them when the entry is pruned. No lock
# anywhere: the only shared write is the rename, and the loser of a race discards its build.
set -euo pipefail

store=${WORKOUT_DEP_STORE:-$HOME/Library/Caches/workout-dep-store}

usage() {
  cat <<'EOF'
Usage: scripts/dep-store.sh key [-s <string>]... [<file>]...
       scripts/dep-store.sh publish <key> <command> [arg...]
       scripts/dep-store.sh clone <key> <dest>
       scripts/dep-store.sh prune --keep-bytes <n>
       scripts/dep-store.sh list

The store is WORKOUT_DEP_STORE (~/Library/Caches/workout-dep-store), on the same APFS volume as
the worktrees and DerivedData so clones share blocks. Lanes never read a path inside it.

  key      print the sha256 of the inputs that determine an entry's content, in the order given:
           each file's bytes and each -s string. The same inputs always give the same key.
  publish  when entries/<key> is missing, run the command with DEP_STORE_OUT set to an empty
           private directory, then publish that directory as the entry with one rename. A command
           that exits nonzero or writes nothing publishes nothing, and publish exits with its
           status (70 for nothing written). When another producer published <key> first, this
           build is discarded and publish exits 0. When the entry already exists, the command
           never runs. Prints nothing on stdout; one status line on stderr.
  clone    clone entries/<key> to <dest>, which must not exist yet (its parent is created), and
           mark the entry used. Exits 3 when there is no such entry, so a caller can publish and
           clone again. Exits 70 after removing <dest> when the copy failed part way, as when the
           entry was pruned during the clone.
  prune    remove entries, least recently cloned first, until the entries total at most <n>
           bytes; never one cloned in the last WORKOUT_DEP_STORE_GRACE_MINUTES (10), which also
           protects a clone in flight. Also removes staging dirs whose producer is dead.
  list     one line per entry: key, KiB, last cloned.
EOF
}

die() { echo "dep-store: $2" >&2; exit "$1"; }
check_key() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || die 2 "key '$1' must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
}
prepare_store() {
  mkdir -p "$store/entries" "$store/staging" || die 70 "could not create $store"
  store=$(cd "$store" && pwd -P)
}
# A staging dir is <producer pid>.<key>.XXXXXX. One whose producer is gone is a crashed build.
sweep_staging() {
  local d pid
  for d in "$store"/staging/*; do
    [ -d "$d" ] || continue
    pid=${d##*/}
    pid=${pid%%.*}
    [ "$pid" != "$$" ] || continue
    kill -0 "$pid" 2>/dev/null && continue
    rm -rf "$d"
  done
}

key() {
  [ $# -gt 0 ] || { usage >&2; exit 2; }
  local parts=()
  while [ $# -gt 0 ]; do
    case $1 in
      -s)
        [ $# -ge 2 ] || die 2 "-s needs a value"
        parts+=("str:$2")
        shift 2
        ;;
      *)
        [ -f "$1" ] || die 2 "not a file: $1"
        parts+=("file:$(shasum -a 256 "$1" | cut -c1-64)")
        shift
        ;;
    esac
  done
  printf '%s\n' "${parts[@]}" | shasum -a 256 | cut -c1-64
}

publish() {
  [ $# -ge 2 ] || { usage >&2; exit 2; }
  local key=$1 entry staging rc started
  shift
  check_key "$key"
  prepare_store
  entry=$store/entries/$key
  if [ -d "$entry/payload" ]; then
    echo "dep-store: $key is already published" >&2
    return 0
  fi
  sweep_staging
  staging=$(mktemp -d "$store/staging/$$.$key.XXXXXX") || die 70 "could not create a staging dir in $store/staging"
  mkdir "$staging/payload"
  started=$(date +%s)
  set +e
  DEP_STORE_OUT=$staging/payload "$@"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    rm -rf "$staging"
    die "$rc" "producer exited $rc; nothing published for $key"
  fi
  if [ -z "$(ls -A "$staging/payload")" ]; then
    rm -rf "$staging"
    die 70 "producer wrote nothing to \$DEP_STORE_OUT; nothing published for $key"
  fi
  printf 'key=%s\nproduced-at=%s\nproducer-pid=%s\nstaged-in=%s\n' "$key" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$staging/payload" >"$staging/meta"
  touch "$staging/used"
  if python3 -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$staging" "$entry" 2>/dev/null; then
    echo "dep-store: published $key ($(du -sk "$entry/payload" | cut -f1) KiB in $(($(date +%s) - started)) s)" >&2
    return 0
  fi
  rm -rf "$staging"
  [ -d "$entry/payload" ] || die 70 "could not publish $key into $store/entries"
  echo "dep-store: $key was published by another producer meanwhile; this build is discarded" >&2
}

clone() {
  [ $# -eq 2 ] || { usage >&2; exit 2; }
  local key=$1 dest=$2 entry parent
  check_key "$key"
  prepare_store
  entry=$store/entries/$key
  [ -d "$entry/payload" ] || { echo "dep-store: no entry $key" >&2; return 3; }
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || die 2 "$dest exists; clone into a path that does not exist yet"
  parent=$(dirname "$dest")
  mkdir -p "$parent" || die 70 "could not create $parent"
  touch "$entry/used"
  if ! cp -c -R "$entry/payload" "$dest"; then
    rm -rf "$dest"
    die 70 "clone of $key into $dest failed part way, so $dest was removed; publish $key again"
  fi
  [ "$(stat -f %d "$entry")" = "$(stat -f %d "$parent")" ] \
    || echo "dep-store: warning: $dest is on another volume than $store, so cp -c copied instead of cloning" >&2
}

# Prints "<used epoch> <KiB> <key>" per entry, least recently used first.
entries_by_use() {
  local e
  for e in "$store"/entries/*; do
    [ -d "$e/payload" ] || continue
    printf '%s %s %s\n' "$(stat -f %m "$e/used" 2>/dev/null || echo 0)" "$(du -sk "$e" | cut -f1)" "${e##*/}"
  done | sort -n
}

prune() {
  local keep='' grace=${WORKOUT_DEP_STORE_GRACE_MINUTES:-10} total=0 now used kib key removed=0
  while [ $# -gt 0 ]; do
    case $1 in
      --keep-bytes) [ $# -ge 2 ] && [[ $2 =~ ^[0-9]+$ ]] || die 2 "--keep-bytes needs a byte count"; keep=$2; shift 2 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$keep" ] || { usage >&2; exit 2; }
  prepare_store
  sweep_staging
  now=$(date +%s)
  while read -r used kib key; do
    [ -n "$key" ] || continue
    total=$((total + kib * 1024))
  done <<<"$(entries_by_use)"
  while read -r used kib key; do
    [ -n "$key" ] || continue
    [ "$total" -gt "$keep" ] || break
    if [ $((now - used)) -lt $((grace * 60)) ]; then
      echo "dep-store: $key was cloned $(((now - used) / 60)) min ago, inside the $grace min grace; keeping it and every newer entry" >&2
      break
    fi
    rm -rf "$store/entries/$key"
    total=$((total - kib * 1024))
    removed=$((removed + 1))
    echo "dep-store: pruned $key ($kib KiB, last cloned $(date -r "$used" +%Y-%m-%dT%H:%M:%S))" >&2
  done <<<"$(entries_by_use)"
  echo "dep-store: pruned $removed entr$([ "$removed" -eq 1 ] && echo y || echo ies); $((total / 1024)) KiB stay in $store/entries" >&2
}

list() {
  prepare_store
  local used kib key
  while read -r used kib key; do
    [ -n "$key" ] || continue
    printf '%s\t%s KiB\tlast cloned %s\n' "$key" "$kib" "$(date -r "$used" +%Y-%m-%dT%H:%M:%S)"
  done <<<"$(entries_by_use)"
}

case ${1:-} in
  -h | --help) usage ;;
  key | publish | clone | prune | list)
    verb=$1
    shift
    "$verb" "$@"
    ;;
  *) usage >&2; exit 2 ;;
esac
