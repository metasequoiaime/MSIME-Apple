#!/bin/bash
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
out=$(mktemp "${TMPDIR:-/tmp}/msime-backend-account-tests.XXXXXX")
trap 'rm -f "$out"' EXIT
sources=()
for source in "$root"/shared/backend/*.swift "$root"/shared/backend-ui/*.swift "$root"/platforms/macos/Backend*.swift; do
  if [[ ${source##*/} != Package.swift ]]; then sources+=("$source"); fi
done
swift_target=${MSIME_SWIFT_TARGET:-$(uname -m)-apple-macosx${MACOSX_DEPLOYMENT_TARGET:-13.0}}
xcrun swiftc -parse-as-library -emit-executable -target "$swift_target" \
  -o "$out" "${sources[@]}" "$root/platforms/macos/tests/BackendAccountTests.swift"
"$out"
