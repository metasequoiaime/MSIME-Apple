#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
out=${TMPDIR:-/tmp}/msime-backend-account-tests.$$
trap 'rm -f "$out"' EXIT
sources=$(find "$root/shared/backend" "$root/shared/backend-ui" "$root/platforms/macos" -maxdepth 1 -name '*.swift' ! -name 'Package.swift' -print)
swiftc -parse-as-library -emit-executable -o "$out" $sources "$root/platforms/macos/tests/BackendAccountTests.swift"
"$out"
