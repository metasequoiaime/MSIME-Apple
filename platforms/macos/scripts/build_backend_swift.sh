#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
output=${1:-"$root/.build/macos/libMSIMEBackend.dylib"}
module_dir=$(dirname "$output")
mkdir -p "$module_dir"
backend_sources=$(find "$root/shared/backend" -maxdepth 1 -name '*.swift' ! -name 'Package.swift' -print)
backend_ui_sources=$(find "$root/shared/backend-ui" -maxdepth 1 -name '*.swift' -print)
mac_sources=$(find "$root/platforms/macos" -maxdepth 1 -name 'Backend*.swift' -print)

exec xcrun swiftc -parse-as-library -emit-library -emit-module \
  -module-name MSIMEBackend -emit-module-path "${output%.dylib}.swiftmodule" \
  -o "$output" $backend_sources $backend_ui_sources $mac_sources
