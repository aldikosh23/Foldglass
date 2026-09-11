#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
app_dir="$project_dir/build/Foldglass.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 \
  "$project_dir"/Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework ScreenCaptureKit \
  -framework Metal -framework MetalKit -framework MetalPerformanceShaders -framework IOKit -framework ServiceManagement \
  -o "$app_dir/Contents/MacOS/Foldglass"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/Fold.metal" "$app_dir/Contents/Resources/Fold.metal"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$project_dir"/Resources/*.lproj "$app_dir/Contents/Resources/"
plutil -lint "$app_dir"/Contents/Resources/*.lproj/*.strings
codesign --force --sign - --identifier local.foldglass \
  --requirements '=designated => identifier "local.foldglass"' "$app_dir"
codesign --verify --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
print -r -- "$app_dir"
