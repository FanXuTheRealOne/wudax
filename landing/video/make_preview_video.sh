#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

mkdir -p assets/video

ffmpeg -y \
  -loop 1 -t 6 -i design/ink_mountains.png \
  -loop 1 -t 7 -i design/01_home.png \
  -loop 1 -t 7 -i design/02_budget_card.png \
  -loop 1 -t 7 -i design/04_gatekeeper.png \
  -loop 1 -t 8 -i design/05_checkin.png \
  -loop 1 -t 8 -i design/06_retreat.png \
  -loop 1 -t 7 -i design/08_exo.png \
  -filter_complex "\
[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v0];\
[1:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v1];\
[2:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v2];\
[3:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v3];\
[4:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v4];\
[5:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v5];\
[6:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=F3F6F0,setsar=1,fps=30[v6];\
[v0][v1][v2][v3][v4][v5][v6]concat=n=7:v=1:a=0,format=yuv420p[v]" \
  -map "[v]" \
  -r 30 \
  -c:v libx264 \
  -preset medium \
  -crf 23 \
  -movflags +faststart \
  assets/video/wudax-launch.mp4
