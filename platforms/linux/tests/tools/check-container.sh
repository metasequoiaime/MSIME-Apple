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
main_worktree=$(dirname "$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null || echo "$repo_root")")
vendor=""
for candidate in "$repo_root/vendor" "$main_worktree/vendor"; do
  [[ -d $candidate/MSIME-Engine ]] && vendor=$(cd "$candidate" && pwd) && break
done
# Docker cannot create the /source/vendor mountpoint inside the read-only /source mount, and a worktree has no vendor/ of its own, so leave an empty (ignored) one for it. The build then uses the mounted tree as it is instead of fetching into it.
[[ -z $vendor ]] || mkdir -p "$repo_root/vendor"
docker build -t msime-client-linux-test:local -f "$repo_root/platforms/linux/tests/tools/Dockerfile" "$repo_root/platforms/linux/tests"
test_image=msime-client-linux-test:local
if [[ ${2:-} == --ibus-1.5.32 ]]; then
  test_image=msime-client-linux-ibus132-test:local
  docker build -t "$test_image" -f "$repo_root/platforms/linux/tests/tools/Dockerfile.ibus-1.5.32" "$repo_root/platforms/linux/tests"
fi
if [[ ${2:-} == --fcitx5 ]]; then
  test_image=msime-client-linux-fcitx5-test:local
  docker build -t "$test_image" -f "$repo_root/platforms/linux/tests/tools/Dockerfile.fcitx5" "$repo_root/platforms/linux/tests"
fi
docker run --rm --init \
  -v "$repo_root:/source:ro" -v "$repo_root/target/linux:/build" -v "$resource_dir:/resources:ro" \
  ${vendor:+-v "$vendor:/source/vendor:ro"} \
  ${vendor:+-e MSIME_SKIP_ENGINE_FETCH=1} \
  -e CARGO_TARGET_DIR=/build/cargo -e CARGO_HOME=/build/cargo-home -e CARGO_BUILD_JOBS=4 \
  -e MSIME_ISOLATED_LINUX_TEST=1 \
  -e MSIME_TEST_FCITX5=$( [[ ${2:-} == --fcitx5 ]] && echo 1 || echo 0 ) \
  "$test_image" bash platforms/linux/tests/tools/in-container.sh
