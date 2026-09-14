#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
# The fake Cargo checks invocation only; this is not an iOS binary test.
export PATH="$repo_root/platforms/ios/tests/tools:$PATH"
export MSIME_IOS_DEPS="$repo_root/platforms/ios/tests"
export IPHONEOS_DEPLOYMENT_TARGET=16.2
export RUSTFLAGS="-C debuginfo=1"
for variant in device simulator; do
  export MSIME_TEST_VARIANT="$variant"
  set +e
  bash "$repo_root/platforms/ios/build-native.sh" "$variant"
  result=$?
  set -e
  # Fake Cargo returns 42 after validation, so no output archive is published.
  [[ "$result" == 42 ]] || exit 1
done
echo "iOS Cargo invocation checks passed (device and simulator)"
