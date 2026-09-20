#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tiler="$root/scripts/contact-sheet.swift"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expect() {
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
        return
    fi
    printf 'FAIL %s: got %s, want %s\n' "$1" "$2" "$3" >&2
    exit 1
}

refute() {
    if [ "$2" != "$3" ]; then
        printf 'ok   %s\n' "$1"
        return
    fi
    printf 'FAIL %s: got %s, want anything else\n' "$1" "$2" >&2
    exit 1
}

size_of() {
    sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}'
}

field() {
    printf '%s\n' "$1" | cut -f"$2"
}

presence() {
    [ -e "$1" ] && echo present || echo absent
}

bytes_at() {
    local hex value=0 i
    hex=$(xxd -p -s "$2" -l "$3" "$1")
    for (( i = $3 - 1; i >= 0; i-- )); do
        value=$(( value * 256 + 0x${hex:$((i * 2)):2} ))
    done
    printf '%d' "$value"
}

# sips is the only image tool on a stock machine and it reports no pixel values, so the probe goes
# through BMP: the one format it writes that a shell can index, with a fixed header and no rows to
# decompress. A negative stored height means the rows run top-down.
pixel_at() {
    local sheet=$1 x=$2 y=$3 bmp="$tmp/probe.bmp" start width height bits stride row at bgr
    sips -s format bmp "$sheet" --out "$bmp" >/dev/null
    start=$(bytes_at "$bmp" 10 4)
    width=$(bytes_at "$bmp" 18 4)
    height=$(bytes_at "$bmp" 22 4)
    bits=$(bytes_at "$bmp" 28 2)
    stride=$(( (bits * width + 31) / 32 * 4 ))
    if [ "$height" -gt 2147483647 ]; then row=$y; else row=$(( height - 1 - y )); fi
    at=$(( start + row * stride + x * bits / 8 ))
    bgr=$(xxd -p -s "$at" -l 3 "$bmp")
    printf '%s%s%s' "${bgr:4:2}" "${bgr:2:2}" "${bgr:0:2}"
}

baselines=("$root"/Tests/Visual/__Snapshots__/*/*.png)
seed="${baselines[0]}"
mkdir -p "$tmp/in" "$tmp/out" "$tmp/bad"
sips -z 2622 1206 "$seed" --out "$tmp/in/phone.png" >/dev/null
sips -z 2556 1179 "$seed" --out "$tmp/in/pick.png" >/dev/null
sips -z 200 92 "$seed" --out "$tmp/in/small.png" >/dev/null
printf 'not an image\n' >"$tmp/in/notes.txt"

phones=()
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
    cp "$tmp/in/phone.png" "$tmp/in/$n.png"
    phones+=("$tmp/in/$n.png")
done
twelve=("${phones[@]:0:12}")

sheet="$tmp/out/sheet.png"
line=$("$tiler" "$sheet" "${twelve[@]}")
size=$(size_of "$sheet")
expect "twelve 1206x2622 frames fit one page" "$size" "2000x1488"
expect "the line counts the images" "$(field "$line" 3)" "12 images"
expect "the line estimates the read cost" "$(field "$line" 4)" "about 3888 tokens"
expect "the legend numbers the cells in argument order" "$(field "$line" 5 | cut -c1-12)" "1. 01  2. 02"
expect "twelve images need no second page" "$(presence "$tmp/out/sheet-2.png")" "absent"
expect "twelve portrait frames solve to 6 columns by 2 rows" "$([ "${size%x*}" -gt "${size#*x}" ] && echo wider || echo taller)" "wider"
refute "not the 4-column grid" "$size" "1192x1994"

cp "$sheet" "$tmp/first.png"
"$tiler" "$sheet" "${twelve[@]}" >/dev/null
expect "the same command again writes the same bytes" "$(cmp -s "$tmp/first.png" "$sheet" && echo identical || echo different)" "identical"

many="$tmp/out/many.png"
lines=$("$tiler" "$many" "${phones[@]}")
page_one=$(printf '%s\n' "$lines" | awk 'NR==1')
page_two=$(printf '%s\n' "$lines" | awk 'NR==2')
expect "thirteen images balance across two pages" "$(field "$page_one" 3)/$(field "$page_two" 3)" "7 images/6 images"
expect "page 1 fills the long edge" "$(size_of "$many")" "1804x1996"
expect "page 2 keeps page 1's cell size" "$(size_of "$tmp/out/many-2.png")" "1355x1996"
expect "the legend keeps counting on page 2" "$(field "$page_two" 5 | cut -c1-5)" "8. 08"

"$tiler" "$many" "${twelve[@]}" >/dev/null
expect "a rerun that needs fewer pages removes the stale one" "$(presence "$tmp/out/many-2.png")" "absent"

cp "$tmp/in/01.png" "$tmp/out/many-4.png"
cp "$tmp/in/01.png" "$tmp/out/many-more.png"
"$tiler" "$many" "${twelve[@]}" >/dev/null
expect "a stale page past a gap goes too" "$(presence "$tmp/out/many-4.png")" "absent"
expect "a file that is not one of this sheet's pages stays" "$(presence "$tmp/out/many-more.png")" "present"

image_top=$(( 8 + 28 ))
inside_cell_one=$(( 8 + 4 ))
inside_cell_three=$(( 8 + 2 * (656 + 8) + 4 ))
letterbox_depth=2
triptych="$tmp/out/triptych.png"
"$tiler" "$triptych" "$tmp/in/01.png" "$tmp/in/02.png" "$tmp/in/pick.png" >/dev/null
expect "a 1179x2556 pick shares a grid with two 1206x2622 frames" "$(size_of "$triptych")" "2000x1470"
expect "the sheet background" "$(pixel_at "$triptych" 0 0)" "292929"
expect "the narrower image is letterboxed at the top of cell 3" "$(pixel_at "$triptych" "$inside_cell_three" "$image_top")" "292929"
refute "cell 3's image starts below that margin" "$(pixel_at "$triptych" "$inside_cell_three" $(( image_top + letterbox_depth )))" "292929"
refute "cell 1 fills the same row, so cell 3 was fitted and not stretched" "$(pixel_at "$triptych" "$inside_cell_one" "$image_top")" "292929"

pair="$tmp/out/pair.png"
line=$("$tiler" "$pair" "$tmp/in/01.png" "$tmp/in/02.png")
expect "two frames take the whole long edge" "$(size_of "$pair")" "1822x1998"
expect "a 2-up costs what two single reads cost" "$(field "$line" 4)" "about 4752 tokens"

dearer=""
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    line=$("$tiler" "$tmp/out/cost.png" "${phones[@]:0:$n}")
    cost=$(field "$line" 4 | tr -dc 0-9)
    if [ "$cost" -gt 4752 ] || [ "$cost" -gt $(( n * 2376 )) ]; then dearer="$dearer $n:$cost"; fi
done
expect "no page costs more than a 2-up, or more than reading its frames one by one" "$dearer" ""

tiny="$tmp/out/tiny.png"
"$tiler" "$tiny" "$tmp/in/small.png" >/dev/null
expect "a 92x200 image is never upscaled to fill the page" "$(size_of "$tiny")" "108x244"

if err=$("$tiler" "$tmp/bad/out.png" "$tmp/in/01.png" "$tmp/in/notes.txt" 2>&1 >/dev/null); then code=0; else code=$?; fi
expect "an unreadable input exits 66" "$code" "66"
case $err in
    *"$tmp/in/notes.txt"*) named=named ;;
    *) named="$err" ;;
esac
expect "the error names the path it could not read" "$named" "named"
expect "nothing is written when an input cannot be read" "$(presence "$tmp/bad/out.png")" "absent"

if "$tiler" >/dev/null 2>&1; then code=0; else code=$?; fi
expect "no arguments exits 64" "$code" "64"
