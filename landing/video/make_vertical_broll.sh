#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

mkdir -p assets/video

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shot() {
  local input="$1"
  local out="$2"
  local duration="$3"
  local out_start
  out_start="$(awk -v d="$duration" 'BEGIN{printf "%.2f", d-0.22}')"

  ffmpeg -y \
    -loop 1 -t "$duration" -i "$input" \
    -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,format=yuv420p,fade=t=in:st=0:d=0.22,fade=t=out:st=${out_start}:d=0.22" \
    -r 30 -c:v libx264 -crf 20 -pix_fmt yuv420p "$out"
}

shot "assets/video/broll-cards/01-coach.png" "$tmpdir/shot1.mp4" 1.7
shot "assets/video/broll-cards/02-analysis.png" "$tmpdir/shot2.mp4" 1.7
shot "assets/video/broll-cards/03-checkin.png" "$tmpdir/shot3.mp4" 1.6
shot "assets/video/broll-cards/04-danger.png" "$tmpdir/shot4.mp4" 1.7
shot "assets/video/broll-cards/05-expert.png" "$tmpdir/shot5.mp4" 1.6

printf "file '%s'\n" "$tmpdir/shot1.mp4" > "$tmpdir/concat.txt"
printf "file '%s'\n" "$tmpdir/shot2.mp4" >> "$tmpdir/concat.txt"
printf "file '%s'\n" "$tmpdir/shot3.mp4" >> "$tmpdir/concat.txt"
printf "file '%s'\n" "$tmpdir/shot4.mp4" >> "$tmpdir/concat.txt"
printf "file '%s'\n" "$tmpdir/shot5.mp4" >> "$tmpdir/concat.txt"

ffmpeg -y \
  -f concat -safe 0 -i "$tmpdir/concat.txt" \
  -c copy -movflags +faststart \
  assets/video/wudax-broll-vertical.mp4
