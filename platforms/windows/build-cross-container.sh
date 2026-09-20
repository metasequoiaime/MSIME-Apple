#!/usr/bin/env bash
# Run build-cross.sh inside the cross container.
#
# Use this when the host has no toolchain the architecture can be built with.
# On macOS that is x86: Homebrew's i686 MinGW uses SJLJ exceptions and Rust's
# i686-pc-windows-gnu needs DWARF unwinding, so build-cross.sh refuses. The
# container carries Debian's i686 MinGW, which is built with DWARF, and the
# build then runs unchanged.
#
# The repository is mounted rather than copied, so the outputs land in the
# usual target/ directories. vcpkg and its dependency tree are built inside the
# container under target/, which means they are kept between runs and are not
# mixed with the host's own (a host-built vcpkg tree carries host binaries).
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arch=${1:-x86}
image=msime-cross:local

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped: docker is not installed"; exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "skipped: the docker daemon is not running"; exit 0
fi
docker build --platform linux/amd64 -t "$image" "$root/platforms/windows/cross" >/dev/null 2>&1 || {
  echo "skipped: could not build the cross image"; exit 0; }

# Keep the container's tooling apart from the host's. A vcpkg checkout
# bootstrapped on macOS holds a macOS vcpkg binary, which cannot run in here,
# and the dependency trees are built for different hosts. bootstrap-vcpkg.sh
# writes to target/tooling by construction, so that path is bind-mounted to a
# container-only directory rather than teaching the script a second location.
mkdir -p "$root/target/tooling-linux" "$root/target/windows-native-deps-linux"
docker run --rm --platform linux/amd64 \
  -v "$root":/repo -v "$root/target/tooling-linux":/repo/target/tooling -w /repo \
  -e MSIME_WINDOWS_DEPS_ROOT=/repo/target/windows-native-deps-linux \
  "$image" bash platforms/windows/build-cross.sh "$arch"
