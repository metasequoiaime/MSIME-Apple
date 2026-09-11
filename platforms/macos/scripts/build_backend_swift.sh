#!/bin/bash
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
output=${1:-"$root/.build/macos/libMSIMEBackend.dylib"}
module_dir=$(dirname "$output")
mkdir -p "$module_dir"
sources=()
for source in "$root"/shared/backend/*.swift "$root"/shared/backend-ui/*.swift "$root"/platforms/macos/Backend*.swift; do
  if [[ ${source##*/} != Package.swift ]]; then sources+=("$source"); fi
done
swift_target=${MSIME_SWIFT_TARGET:-$(uname -m)-apple-macosx${MACOSX_DEPLOYMENT_TARGET:-13.0}}

exec xcrun swiftc -parse-as-library -emit-library -emit-module \
  -module-name MSIMEBackend -emit-module-path "${output%.dylib}.swiftmodule" \
  -target "$swift_target" -Xlinker -install_name -Xlinker "@rpath/$(basename "$output")" \
  -o "$output" "${sources[@]}"
