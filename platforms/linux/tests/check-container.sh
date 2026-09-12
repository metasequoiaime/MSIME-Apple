#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
[[ ( $# == 1 || ( $# == 2 && $2 == --ibus-1.5.32 ) ) && -d "$1" ]] || {
  echo "usage: check-container.sh <locked-resource-directory> [--ibus-1.5.32]" >&2
  exit 2
}
resource_dir=$(cd "$1" && pwd)
mkdir -p "$repo_root/target/linux"
docker build -t msime-client-linux-test:local -f "$repo_root/platforms/linux/tests/Dockerfile" "$repo_root/platforms/linux/tests"
test_image=msime-client-linux-test:local
if [[ ${2:-} == --ibus-1.5.32 ]]; then
  test_image=msime-client-linux-ibus132-test:local
  docker build -t "$test_image" -f "$repo_root/platforms/linux/tests/Dockerfile.ibus-1.5.32" "$repo_root/platforms/linux/tests"
fi
docker run --rm --init \
  -v "$repo_root:/source:ro" -v "$repo_root/target/linux:/build" -v "$resource_dir:/resources:ro" \
  -e CARGO_TARGET_DIR=/build/cargo -e CARGO_HOME=/build/cargo-home -e CARGO_BUILD_JOBS=4 \
  -e MSIME_ISOLATED_LINUX_TEST=1 "$test_image" \
  bash platforms/linux/tests/in-container.sh
