#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: .agents/skills/pr-evidence/evidence.sh <command> [args]
  gif [--from S] [--to S] [--width PX] [--fps N] TAKE.mp4
            write TAKE.gif beside TAKE.mp4 and print its path. It starts 0.3 s before the screen first
            changes, because a take's recorder holds one frame until then; --from and --to pick the
            seconds instead. Defaults: 360 px wide, 15 fps
  publish [--name NAME] [--width PX] FILE...
            commit FILE... onto the branch evidence/NAME on origin (NAME defaults to the current
            branch), keeping every file an earlier publish put there, and print one Markdown line per
            file for the PR body: an <img> for .png .jpg .jpeg .gif, a link for anything else.
            Each URL names the commit, so a later publish never changes an image already in a body.
            --width sets the <img> width in pixels (default 300)
  check PR  fetch PR's rendered body and fetch every image in it; exit 1 unless each one answers
            200 with an image/* type
EOF
  exit 2
}

slug() {
  local url
  url=$(git config --get remote.origin.url) || { echo "no origin remote" >&2; exit 2; }
  url=${url%.git}
  case "$url" in
    *github.com[:/]*) echo "${url##*github.com[:/]}" ;;
    *) echo "origin is not a GitHub remote: $url" >&2; exit 2 ;;
  esac
}

ident() {
  git var GIT_AUTHOR_IDENT >/dev/null 2>&1 && return 0
  local login
  login=$(gh api user -q .login 2>/dev/null) || login=pr-evidence
  export GIT_AUTHOR_NAME=$login GIT_COMMITTER_NAME=$login
  export GIT_AUTHOR_EMAIL=$login@users.noreply.github.com GIT_COMMITTER_EMAIL=$login@users.noreply.github.com
}

gif() {
  local from="" to="" width=360 fps=15
  while [ $# -gt 0 ]; do
    case "$1" in
      --from|--to|--width|--fps)
        [ $# -ge 2 ] && [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage
        case "$1" in --from) from=$2 ;; --to) to=$2 ;; --width) width=$2 ;; --fps) fps=$2 ;; esac
        shift 2 ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  [ $# -eq 1 ] || usage
  local take=$1 out=${1%.*}.gif changed
  [ -f "$take" ] || { echo "no such file: $take" >&2; exit 2; }
  if [ -z "$from" ]; then
    changed=$(ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$take" | sed -n 2p | tr -d ,)
    from=$(awk -v t="${changed:-0}" 'BEGIN { s = t - 0.3; if (s < 0) s = 0; printf "%.3f", s }')
  fi
  # fps before trim repeats the held frame, so the span opens on the screen before the change.
  ffmpeg -loglevel error -y -i "$take" -vf "fps=$fps,trim=start=$from${to:+:end=$to},setpts=PTS-STARTPTS,\
scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" "$out"
  echo "$out"
}

publish() {
  local name="" width=300
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) [ $# -ge 2 ] || usage; name=$2; shift 2 ;;
      --width) [ $# -ge 2 ] || usage; width=$2; shift 2 ;;
      --) shift; break ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || usage
  if [ -z "$name" ]; then
    name=$(git symbolic-ref --short -q HEAD) || { echo "detached HEAD: pass --name NAME" >&2; exit 2; }
  fi
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo "bad name: $name" >&2; exit 2; }
  [[ $width =~ ^[0-9]+$ ]] || { echo "bad width: $width" >&2; exit 2; }

  local file base seen=" "
  for file in "$@"; do
    [ -f "$file" ] || { echo "no such file: $file" >&2; exit 2; }
    base=${file##*/}
    [[ $base =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "rename it to letters, digits, '.', '_' and '-': $base" >&2; exit 2; }
    case "$seen" in *" $base "*) echo "two files named $base" >&2; exit 2 ;; esac
    seen="$seen$base "
  done

  local ref=refs/heads/evidence/$name repo parent="" tree commit
  repo=$(slug)
  if git ls-remote --exit-code origin "$ref" >/dev/null; then
    git fetch -q origin "$ref"
    parent=$(git rev-parse FETCH_HEAD)
  fi
  index=$(mktemp)
  trap 'rm -f "$index"' EXIT
  if [ -n "$parent" ]; then GIT_INDEX_FILE=$index git read-tree "$parent"; else rm -f "$index"; fi
  for file in "$@"; do
    GIT_INDEX_FILE=$index git update-index --add --cacheinfo "100644,$(git hash-object -w -- "$file"),${file##*/}"
  done
  tree=$(GIT_INDEX_FILE=$index git write-tree)
  if [ -n "$parent" ] && [ "$tree" = "$(git rev-parse "$parent^{tree}")" ]; then
    commit=$parent
  else
    ident
    commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "evidence:${seen% }")
    git push -q origin "$commit:$ref" || { echo "push to $ref failed; someone published at the same time, so rerun" >&2; exit 1; }
  fi

  local url
  for file in "$@"; do
    base=${file##*/}
    url="https://github.com/$repo/blob/$commit/$base?raw=true"
    case "$base" in
      *.png|*.jpg|*.jpeg|*.gif) printf '<img src="%s" width="%s">\n' "$url" "$width" ;;
      *) printf '[%s](%s)\n' "$base" "$url" ;;
    esac
  done
}

check() {
  [ $# -eq 1 ] || usage
  local repo html src got failed=0 count=0
  repo=$(slug)
  html=$(gh api "repos/$repo/pulls/$1" -H 'Accept: application/vnd.github.html+json' -q .body_html)
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    count=$((count + 1))
    got=$(curl -sL -o /dev/null -w '%{http_code} %{content_type}' "$src") || got="curl-failed"
    case "$got" in
      "200 image/"*) echo "ok   ${got#200 } $src" ;;
      *) echo "FAIL $got $src"; failed=1 ;;
    esac
  done < <(printf '%s' "$html" | grep -o '<img [^>]*src="[^"]*"' | sed 's/.*src="\([^"]*\)"/\1/' | sed 's/&amp;/\&/g')
  if [ "$count" -eq 0 ]; then
    echo "FAIL PR $1 renders no images"
    failed=1
  fi
  return "$failed"
}

[ $# -gt 0 ] || usage
cmd=$1
shift
case "$cmd" in
  gif) gif "$@" ;;
  publish) publish "$@" ;;
  check) check "$@" ;;
  *) usage ;;
esac
