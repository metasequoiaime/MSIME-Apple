#!/usr/bin/env bash
# Run the cross-built Windows test executables under Wine, in a container.
#
# These suites were built by build-cross.sh and then never run: executing a
# Windows binary needs Windows, so every report about them said "linked".
# Linking does not catch an assertion. Wine runs 72 of them as they are, which
# is the difference between a suite that compiles and a suite that passes.
#
# What it cannot run is recorded rather than hidden: anything that needs a
# compositor, a real monitor, or the installed dictionary bundle fails here for
# the environment, the same way it does on a Windows session with no desktop.
# Those names are compared against scripts/known-failures.txt, so the question
# this answers is the same one the rest of local verification answers - did
# this change break something that worked.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
arch=${1:-x64}
build="$root/target/windows-full/$arch"
image=msime-wine:local

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped: docker is not installed"
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "skipped: the docker daemon is not running"
  exit 0
fi
if [ ! -d "$build" ]; then
  echo "skipped: $build not built"
  echo "  run platforms/windows/build-cross.sh $arch first"
  exit 0
fi

# The MinGW runtime is not bundled beside the executables, so collect it from
# the toolchain that produced them rather than copying it into the build tree.
compiler=$(command -v x86_64-w64-mingw32-g++ 2>/dev/null) || {
  echo "skipped: x86_64-w64-mingw32-g++ is not installed"; exit 0; }
# Ask the compiler where its own files live rather than searching a prefix: the
# same package ships an i686 toolchain with identically named DLLs, and picking
# those makes every x86_64 executable fail to load - which reads as the whole
# suite failing rather than as a runner mistake.
toolchain="$("$compiler" -print-sysroot 2>/dev/null)"
[ -n "$toolchain" ] && [ -d "$toolchain" ] ||
  toolchain="$(dirname "$("$compiler" -print-libgcc-file-name 2>/dev/null)")"
runtime="$(mktemp -d)"
trap 'rm -rf "$runtime"' EXIT
found=0
for name in libwinpthread-1.dll libstdc++-6.dll libgcc_s_seh-1.dll; do
  path=$(find "$toolchain" -name "$name" -print -quit 2>/dev/null)
  [ -n "$path" ] && cp "$path" "$runtime/" && found=$((found + 1))
done
if [ "$found" -ne 3 ]; then
  echo "skipped: the MinGW runtime DLLs are not where this toolchain keeps them"
  exit 0
fi

docker build --platform linux/amd64 -t "$image" "$root/platforms/windows/wine" >/dev/null 2>&1 || {
  echo "skipped: could not build the Wine image"; exit 0; }

# windows-session-smoke takes an optional resource directory and needs one to
# get past its candidate-translation checks - the dictionaries are release
# artefacts the cross build does not stage. Point MSIME_WINE_RESOURCES at a
# directory holding what resources/desktop-dictionary.lock.json lists and it is
# passed through; without it the suite runs as far as it can.
# bash 3.2 treats an empty array as unset under `set -u`, so every expansion
# of it has to be guarded rather than written plainly.
resources_mount=()
resources_argument=""
if [ -n "${MSIME_WINE_RESOURCES:-}" ] && [ -d "${MSIME_WINE_RESOURCES}" ]; then
  resources_mount=(-v "${MSIME_WINE_RESOURCES}":/res:ro)
  resources_argument='Z:\\res'
fi

docker run --rm --platform linux/amd64 \
  -v "$build":/bin-win:ro -v "$runtime":/rt:ro ${resources_mount[@]+"${resources_mount[@]}"} \
  -e "MSIME_RESOURCES=$resources_argument" "$image" sh -c '
mkdir -p /run/t && cp /rt/*.dll /run/t/ && cp /bin-win/*.dll /run/t/ 2>/dev/null
cd /run/t
for exe in /bin-win/windows-*.exe /bin-win/msime-tsf-*.exe /bin-win/msimeui-tests.exe; do
  [ -f "$exe" ] || continue
  name=$(basename "$exe" .exe)
  cp "$exe" /run/t/ 2>/dev/null || continue
  argument=""
  [ "$name" = windows-session-smoke ] && argument="$MSIME_RESOURCES"
  if timeout 120 xvfb-run -a wine "/run/t/$name.exe" $argument >/dev/null 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name"
  fi
done'
