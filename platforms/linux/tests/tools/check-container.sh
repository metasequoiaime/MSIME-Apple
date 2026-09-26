#!/usr/bin/env bash
set -euo pipefail
# Four levels: this script sits in platforms/linux/tests/tools. It said three
# when it lived one directory up, and nothing has been able to run it since that
# move - docker build was handed platforms/platforms/linux/tests as its context.
repo_root=$(cd "$(dirname "$0")/../../../.." && pwd)
[[ ( $# == 1 || ( $# == 2 && ( $2 == --ibus-1.5.32 || $2 == --fcitx5 ) ) ) && -d "$1" ]] || {
  echo "usage: check-container.sh <locked-resource-directory> [--ibus-1.5.32|--fcitx5]" >&2
  exit 2
}
resource_dir=$(cd "$1" && pwd)
mkdir -p "$repo_root/target/linux"
# /source is mounted read-only, so the Engine archive has to be there already -
# and in a worktree it is not, because vendor/ is ignored and lives in whichever
# checkout last fetched it. Mount that one rather than making this run impossible
# from the working style this repository actually uses. Same lookup order as the
# Windows gate's vcpkg tree and platforms/linux/build-container.sh.
# A tree prepared for a different lock (same Engine commit, older overlays) builds against the wrong Engine source, so only one matching this checkout's engine-lock.json is borrowed.
vendor=$(python3 "$repo_root/scripts/fetch_engine.py" --borrowable)
# The container cannot fetch into the read-only /source, so prepare this checkout's own tree on the host when nothing matches.
if [[ -z $vendor ]]; then
  python3 "$repo_root/scripts/fetch_engine.py"
  vendor="$repo_root/vendor"
fi
# Docker cannot create the /source/vendor mountpoint inside the read-only /source mount, and a worktree has no vendor/ of its own, so leave an empty (ignored) one for it. The build then uses the mounted tree as it is instead of fetching into it.
[[ -z $vendor ]] || mkdir -p "$repo_root/vendor"
# Tag per checkout, as build-container.sh does: with a fixed tag, concurrent worktrees overwrite each other's image and a run can silently test another checkout's Dockerfile.
tag=$(printf %s "$repo_root" | shasum | cut -c1-12)
base_image=msime-linux-test:$tag
docker build -t "$base_image" -f "$repo_root/platforms/linux/tests/tools/Dockerfile" "$repo_root/platforms/linux/tests"
test_image=$base_image
if [[ ${2:-} == --ibus-1.5.32 ]]; then
  test_image=msime-linux-ibus132-test:$tag
  docker build -t "$test_image" --build-arg BASE_IMAGE="$base_image" -f "$repo_root/platforms/linux/tests/tools/Dockerfile.ibus-1.5.32" "$repo_root/platforms/linux/tests"
fi
if [[ ${2:-} == --fcitx5 ]]; then
  test_image=msime-linux-fcitx5-test:$tag
  docker build -t "$test_image" --build-arg BASE_IMAGE="$base_image" -f "$repo_root/platforms/linux/tests/tools/Dockerfile.fcitx5" "$repo_root/platforms/linux/tests"
fi
docker run --rm --init \
  -v "$repo_root:/source:ro" -v "$repo_root/target/linux:/build" -v "$resource_dir:/resources:ro" \
  ${vendor:+-v "$vendor:/source/vendor:ro"} \
  ${vendor:+-e MSIME_SKIP_ENGINE_FETCH=1} \
  -e CARGO_TARGET_DIR=/build/cargo -e CARGO_HOME=/build/cargo-home -e CARGO_BUILD_JOBS=4 \
  -e MSIME_ISOLATED_LINUX_TEST=1 \
  -e MSIME_TEST_FCITX5=$( [[ ${2:-} == --fcitx5 ]] && echo 1 || echo 0 ) \
  "$test_image" bash platforms/linux/tests/tools/in-container.sh
