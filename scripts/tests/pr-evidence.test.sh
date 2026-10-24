#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
evidence="$script_dir/../../.agents/skills/pr-evidence/evidence.sh"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_exit() {
    if [ "$2" -eq "$3" ]; then ok "$1 exits $3"; else bad "$1 exits $3, got $2: $out"; fi
}

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3"; fi
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init -q --bare "$tmp/remote.git"
git init -q -b feat/rest-pill "$tmp/work"
git -C "$tmp/work" commit -q --allow-empty -m base
git -C "$tmp/work" remote add origin https://github.com/acme/app.git
git -C "$tmp/work" config url."$tmp/remote.git".insteadOf https://github.com/acme/app.git
printf 'png-one' > "$tmp/01-before.png"
printf 'gif-one' > "$tmp/log.gif"
printf 'mp4-one' > "$tmp/log.mp4"

run() {
    out=$(cd "$tmp/work" && "$evidence" "$@" 2>&1)
    status=$?
}

files_on() {
    git -C "$tmp/remote.git" ls-tree --name-only "$1" | tr '\n' ' '
}

echo "publish puts the files on evidence/<branch> and prints a line per file, pinned to the commit"
run publish "$tmp/01-before.png" "$tmp/log.gif" "$tmp/log.mp4"
expect_exit "first publish" "$status" 0
first=$(git -C "$tmp/remote.git" rev-parse refs/heads/evidence/feat/rest-pill)
expect_line "first publish" "$out" "<img src=\"https://github.com/acme/app/blob/$first/01-before.png?raw=true\" width=\"300\">"
expect_line "first publish" "$out" "<img src=\"https://github.com/acme/app/blob/$first/log.gif?raw=true\" width=\"300\">"
expect_line "first publish" "$out" "[log.mp4](https://github.com/acme/app/blob/$first/log.mp4?raw=true)"
if [ "$(files_on "$first")" = "01-before.png log.gif log.mp4 " ]; then ok "the branch holds the three files"; else bad "the branch holds: $(files_on "$first")"; fi
subject=$(git -C "$tmp/remote.git" log -1 --format=%s "$first")
if [ "$subject" = "evidence: 01-before.png log.gif log.mp4" ]; then ok "the commit names the files, not their local paths"; else bad "the commit subject is: $subject"; fi
if [ -z "$(git -C "$tmp/remote.git" rev-list --parents -n 1 "$first" | cut -s -d' ' -f2)" ]; then ok "the first commit has no parent"; else bad "the first commit has a parent"; fi
if [ -z "$(git -C "$tmp/work" status --porcelain)" ] && [ "$(git -C "$tmp/work" rev-list --count HEAD)" -eq 1 ]; then ok "the checkout and its branch are untouched"; else bad "the checkout changed"; fi

echo "a second publish keeps the earlier files and commit, so earlier links still resolve"
printf 'png-two' > "$tmp/02-after.png"
printf 'png-changed' > "$tmp/01-before.png"
run publish --name feat/rest-pill --width 250 "$tmp/02-after.png" "$tmp/01-before.png"
expect_exit "second publish" "$status" 0
second=$(git -C "$tmp/remote.git" rev-parse refs/heads/evidence/feat/rest-pill)
expect_line "second publish" "$out" "<img src=\"https://github.com/acme/app/blob/$second/02-after.png?raw=true\" width=\"250\">"
if git -C "$tmp/remote.git" merge-base --is-ancestor "$first" "$second"; then ok "the first commit is an ancestor of the second"; else bad "the first commit was dropped"; fi
if [ "$(files_on "$second")" = "01-before.png 02-after.png log.gif log.mp4 " ]; then ok "the branch keeps every file"; else bad "the branch holds: $(files_on "$second")"; fi
if [ "$(git -C "$tmp/remote.git" cat-file -p "$first:01-before.png")" = png-one ]; then ok "the first commit still serves the first 01-before.png"; else bad "the first 01-before.png changed"; fi

echo "republishing the same bytes makes no commit"
run publish "$tmp/02-after.png"
expect_exit "same bytes" "$status" 0
if [ "$(git -C "$tmp/remote.git" rev-parse refs/heads/evidence/feat/rest-pill)" = "$second" ]; then ok "the tip did not move"; else bad "the tip moved"; fi

echo "bad input is refused before anything is pushed"
printf 'x' > "$tmp/has space.png"
run publish "$tmp/has space.png"
expect_exit "a name with a space" "$status" 2
mkdir -p "$tmp/other"
printf 'y' > "$tmp/other/log.gif"
run publish "$tmp/log.gif" "$tmp/other/log.gif"
expect_exit "two files with one name" "$status" 2
expect_line "two files with one name" "$out" "two files named log.gif"
git -C "$tmp/work" checkout -q --detach
run publish "$tmp/log.gif"
expect_exit "detached without --name" "$status" 2
expect_line "detached without --name" "$out" "detached HEAD: pass --name NAME"
if [ "$(git -C "$tmp/remote.git" rev-parse refs/heads/evidence/feat/rest-pill)" = "$second" ]; then ok "no refused publish pushed"; else bad "a refused publish pushed"; fi

echo "gif starts 0.3 s before the take's screen first changes, beside the take"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/ffprobe" <<'EOF'
#!/usr/bin/env bash
printf '0.000000,\n3.730000\n3.735000\n'
EOF
cat > "$tmp/bin/ffmpeg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FAKE_FFMPEG_ARGS"
for out; do :; done
: > "$out"
EOF
chmod +x "$tmp/bin/ffprobe" "$tmp/bin/ffmpeg"
export FAKE_FFMPEG_ARGS="$tmp/ffmpeg-args"
printf 'mp4' > "$tmp/take.mp4"
out=$(PATH="$tmp/bin:$PATH" "$evidence" gif "$tmp/take.mp4" 2>&1)
status=$?
expect_exit "gif" "$status" 0
expect_line "gif" "$out" "$tmp/take.gif"
case "$(cat "$FAKE_FFMPEG_ARGS")" in
    "-loglevel error -y -i $tmp/take.mp4 -vf fps=15,trim=start=3.430,setpts=PTS-STARTPTS,scale=360:-1:"*) ok "gif repeats the held frame, then starts at 3.430 s, 360 px wide" ;;
    *) bad "gif ran: $(cat "$FAKE_FFMPEG_ARGS")" ;;
esac
out=$(PATH="$tmp/bin:$PATH" "$evidence" gif --from 1 --to 2.5 --width 200 "$tmp/take.mp4" 2>&1)
case "$(cat "$FAKE_FFMPEG_ARGS")" in
    "-loglevel error -y -i $tmp/take.mp4 -vf fps=15,trim=start=1:end=2.5,setpts=PTS-STARTPTS,scale=200:-1:"*) ok "--from and --to pick the span" ;;
    *) bad "gif --from 1 --to 2.5 ran: $(cat "$FAKE_FFMPEG_ARGS")" ;;
esac

echo "check fetches every rendered image and fails what does not answer as an image"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
cat "$FAKE_HTML"
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
for url; do :; done
case "$url" in
  *'?raw=true') echo "200 image/png" ;;
  *) echo "200 text/html; charset=utf-8" ;;
esac
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH" FAKE_HTML="$tmp/html"
good='https://github.com/acme/app/blob/abc/01-before.png?raw=true'
blob='https://github.com/acme/app/blob/abc/02-after.png'
printf '<p><a href="%s"><img src="%s" width="300" style="max-width: 100%%;"></a></p>' "$good" "$good" > "$tmp/html"
run check 7
expect_exit "every image resolves" "$status" 0
expect_line "every image resolves" "$out" "ok   image/png $good"
printf '<p><img src="%s" width="300"><img src="%s" width="300"></p>' "$good" "$blob" > "$tmp/html"
run check 7
expect_exit "a blob link without ?raw=true" "$status" 1
expect_line "a blob link without ?raw=true" "$out" "FAIL 200 text/html; charset=utf-8 $blob"
printf '<p>no images</p>' > "$tmp/html"
run check 7
expect_exit "no images" "$status" 1
expect_line "no images" "$out" "FAIL PR 7 renders no images"

echo
echo "pr-evidence: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
