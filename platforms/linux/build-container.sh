#!/usr/bin/env bash
# Compile the Linux native host - the IBus engine, the Fcitx5 addon, every
# provider entry point and all the unit tests - and run the tests, in a
# container, so a machine that is not Linux can still hold this gate.
#
# It exists because nothing held it. `verify-local.sh` had no phase for
# platforms/linux at all, and the build had drifted into failing: three tests
# carried relative includes one level short of where the sources moved, and one
# of them could not name its own fixtures. The whole target - the product on this
# platform - would not configure.
#
# This is a compile-and-unit-test gate, not acceptance. It ships no locked
# dictionaries and starts no D-Bus or IBus daemon; tests/tools/check-container.sh
# is the run that does, and it needs a verified resource directory.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"

command -v docker >/dev/null 2>&1 || {
  echo "docker is required; run this on a Linux host instead" >&2
  exit 2
}

# The Engine is an unpacked archive under vendor/, not a checked-in tree, so a
# fresh worktree has none. Mount whichever tree already holds it rather than
# fetching another copy per worktree - the same order the Windows gate uses to
# find its vcpkg.
main_worktree="$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .)")"
vendor=""
for candidate in "$repo_root/vendor" "$main_worktree/vendor"; do
  [ -d "$candidate/MSIME-Engine" ] && vendor="$(cd "$candidate" && pwd)" && break
done

build_root="$repo_root/target/linux-build-gate"
mkdir -p "$build_root"

docker build -q -t msime-client-linux-build-gate:local \
  -f platforms/linux/tests/tools/Dockerfile.build-gate platforms/linux/tests >/dev/null

docker run --rm --init \
  -v "$repo_root":/source \
  ${vendor:+-v "$vendor":/source/vendor:ro} \
  -v "$build_root":/build \
  -w /source \
  -e CARGO_TARGET_DIR=/build/cargo \
  ${vendor:+-e MSIME_SKIP_ENGINE_FETCH=1} \
  msime-client-linux-build-gate:local bash -euo pipefail -c '
    cargo build -p msime-host-api --locked
    cmake -S platforms/linux -B /build/cmake -G Ninja \
      -DMSIME_ENABLE_FCITX5=ON \
      -DMSIME_HOST_LIBRARY=/build/cargo/debug/libmsime_host_api.so
    cmake --build /build/cmake
    ctest --test-dir /build/cmake --output-on-failure
  '
