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
  local frames
  frames="$(awk -v d="$duration" 'BEGIN{printf "%d", d * 30}')"

  ffmpeg -y \
    -loop 1 -i "$input" \
    -vf "scale=1200:2134:force_original_aspect_ratio=increase,crop=1200:2134,zoompan=z='min(zoom+0.00055,1.045)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${frames}:s=1080x1920:fps=30,format=yuv420p" \
    -frames:v "$frames" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p "$out"
}

shot "assets/video/outdoor-broll-frames/01-ai-hiking-coach.png" "$tmpdir/shot1.mp4" 2.3
shot "assets/video/outdoor-broll-frames/02-route-body-analysis.png" "$tmpdir/shot2.mp4" 2.3
shot "assets/video/outdoor-broll-frames/03-local-survival-expert.png" "$tmpdir/shot3.mp4" 2.3
shot "assets/video/outdoor-broll-frames/04-safe-route-guidance.png" "$tmpdir/shot4.mp4" 2.3

ffmpeg -y \
  -i "$tmpdir/shot1.mp4" \
  -i "$tmpdir/shot2.mp4" \
  -i "$tmpdir/shot3.mp4" \
  -i "$tmpdir/shot4.mp4" \
  -filter_complex "[0:v][1:v]xfade=transition=fade:duration=0.35:offset=1.95[v01];[v01][2:v]xfade=transition=fade:duration=0.35:offset=3.90[v02];[v02][3:v]xfade=transition=fade:duration=0.35:offset=5.85[v]" \
  -map "[v]" \
  -r 30 -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart \
  assets/video/wudax-outdoor-broll-vertical.mp4
