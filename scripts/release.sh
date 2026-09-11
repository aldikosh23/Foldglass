#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
"$project_dir/build.sh"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")
mkdir -p "$project_dir/dist"
archive="Foldglass-v${version}-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/build/Foldglass.app" "$project_dir/dist/$archive"
cd "$project_dir/dist"
shasum -a 256 "$archive" > SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
