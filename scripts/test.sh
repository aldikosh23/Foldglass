#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
test_dir="$project_dir/build/tests"
mkdir -p "$test_dir"
swiftc -swift-version 5 -O "$project_dir/Sources/FoldCurve.swift" \
  "$project_dir/Tests/FoldCurveTests.swift" -o "$test_dir/fold-curve"
"$test_dir/fold-curve"
swiftc -swift-version 5 -O "$project_dir/Sources/LoginItem.swift" \
  "$project_dir/Sources/FoldCurve.swift" "$project_dir/Sources/FoldRenderer.swift" \
  "$project_dir/Tests/LaunchContextTests.swift" -framework ServiceManagement \
  -framework AppKit -framework Metal -framework MetalKit -framework MetalPerformanceShaders -o "$test_dir/launch-context"
"$test_dir/launch-context"
if [[ "${RUN_METAL_TESTS:-0}" == "1" ]]; then
  swiftc -swift-version 5 -O "$project_dir/Sources/FoldCurve.swift" \
    "$project_dir/Sources/FoldRenderer.swift" "$project_dir/Sources/DemoImage.swift" \
    "$project_dir/Tests/RenderCheck.swift" -framework Metal -framework MetalKit \
    -framework MetalPerformanceShaders -framework AppKit -o "$test_dir/render-check"
  "$test_dir/render-check" "$project_dir" "$test_dir/frames"
fi
