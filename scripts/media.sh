#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
media_dir="$project_dir/build/docs"
command -v ffmpeg >/dev/null || { print -u2 'ffmpeg is required: brew install ffmpeg'; exit 1; }
mkdir -p "$media_dir/frames"
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  "$project_dir/Tools/ExportMedia.swift" \
  "$project_dir/Sources/FoldCurve.swift" \
  "$project_dir/Sources/FoldRenderer.swift" \
  "$project_dir/Sources/DemoImage.swift" \
  -framework AppKit -framework Metal -framework MetalKit -framework MetalPerformanceShaders \
  -o "$media_dir/export-media"
"$media_dir/export-media" "$project_dir" "$media_dir/frames"
ffmpeg -hide_banner -loglevel error -y -framerate 20 -i "$media_dir/frames/frame-%03d.png" \
  -filter_complex '[0:v]trim=end_frame=120,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
  -frames:v 120 -loop 0 "$project_dir/docs/assets/preview.gif"
print -r -- "$project_dir/docs/assets/hero.png" "$project_dir/docs/assets/preview.gif"
