#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
abi=${1:-arm64-v8a}
case "$abi" in
  arm64-v8a) rust_target=aarch64-unknown-linux-ohos ;;
  armeabi-v7a) rust_target=armv7-unknown-linux-ohos ;;
  x86_64) rust_target=x86_64-unknown-linux-ohos ;;
  *) echo "Supported OpenHarmony ABIs: arm64-v8a, armeabi-v7a, x86_64" >&2; exit 1 ;;
esac
# DevEco Studio ships the NDK inside the app bundle. A standalone command-line SDK works too, as
# long as it points at the directory holding sysroot and build/cmake/ohos.toolchain.cmake.
ndk=${MSIME_OHOS_NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}
if [[ ! -f "$ndk/build/cmake/ohos.toolchain.cmake" ]]; then
  echo "OpenHarmony NDK not found. Install DevEco Studio or set MSIME_OHOS_NDK to a native SDK containing build/cmake/ohos.toolchain.cmake" >&2
  exit 1
fi
# The NDK names its wrappers after the Rust target triple, and each one carries its own --target and
# --sysroot. Using them keeps this script from restating either.
compiler="$ndk/llvm/bin/${rust_target}-clang"
if [[ ! -x "$compiler" ]]; then
  echo "Missing $compiler; this NDK does not provide a wrapper for $rust_target" >&2
  exit 1
fi
# sqlite3 is the only dependency that has to be compiled for the device: boost-algorithm is
# header-only, and fmt and spdlog are consumed as headers here. Build it from the amalgamation with
# the NDK compiler, then lay the result out as a prefix:
#   <prefix>/include/sqlite3.h
#   <prefix>/lib/libsqlite3.a
deps=${MSIME_OHOS_DEPS:-$repo_root/target/ohos-deps/$abi}
if [[ ! -f "$deps/lib/libsqlite3.a" || ! -f "$deps/include/sqlite3.h" ]]; then
  echo "OpenHarmony sqlite3 not found under $deps" >&2
  echo "Build it with:" >&2
  echo "  $compiler -O2 -fPIC -c sqlite3.c -o sqlite3.o" >&2
  echo "  $ndk/llvm/bin/llvm-ar rcs $deps/lib/libsqlite3.a sqlite3.o" >&2
  echo "  cp sqlite3.h $deps/include/" >&2
  echo "Or set MSIME_OHOS_DEPS to a prefix that already has them." >&2
  exit 1
fi
# The OpenHarmony CMake platform confines find_package to its own sysroot, so the header-only
# packages have to be named explicitly. Homebrew is the default source on macOS; override these for
# any other layout.
brew_prefix=$(brew --prefix 2>/dev/null || true)
if [[ -n "$brew_prefix" ]]; then
  boost_version=$(basename "$(find "$brew_prefix/lib/cmake" -maxdepth 1 -name 'Boost-*' | sort | tail -1)" 2>/dev/null || true)
  : "${MSIME_BOOST_DIR:=$brew_prefix/lib/cmake/$boost_version}"
  : "${MSIME_BOOST_HEADERS_DIR:=$brew_prefix/lib/cmake/${boost_version/Boost-/boost_headers-}}"
  : "${MSIME_FMT_DIR:=$brew_prefix/lib/cmake/fmt}"
  : "${MSIME_SPDLOG_DIR:=$brew_prefix/lib/cmake/spdlog}"
fi
for variable in MSIME_BOOST_DIR MSIME_BOOST_HEADERS_DIR MSIME_FMT_DIR MSIME_SPDLOG_DIR; do
  if [[ -z "${!variable:-}" || ! -d "${!variable}" ]]; then
    echo "$variable must point at an existing CMake package directory" >&2
    exit 1
  fi
done
cargo_linker="CARGO_TARGET_$(printf '%s' "$rust_target" | tr '[:lower:]-' '[:upper:]_')_LINKER"
underscored=${rust_target//-/_}
env "CC_${underscored}=$compiler" "CXX_${underscored}=${compiler}++" \
  "AR_${underscored}=$ndk/llvm/bin/llvm-ar" "$cargo_linker=$compiler" \
  MSIME_OHOS_NDK="$ndk" MSIME_OHOS_DEPS="$deps" \
  MSIME_BOOST_DIR="$MSIME_BOOST_DIR" MSIME_BOOST_HEADERS_DIR="$MSIME_BOOST_HEADERS_DIR" \
  MSIME_FMT_DIR="$MSIME_FMT_DIR" MSIME_SPDLOG_DIR="$MSIME_SPDLOG_DIR" \
  CARGO_TARGET_DIR="$repo_root/target/ohos-cargo" \
  cargo build -p msime-host-api --target "$rust_target" --release --locked
output="$repo_root/target/ohos/libs/$abi"
mkdir -p "$output"
cp "$repo_root/target/ohos-cargo/$rust_target/release/libmsime_host_api.so" "$output/"
"$ndk/llvm/bin/llvm-readobj" --file-headers "$output/libmsime_host_api.so" | grep -q "EM_AARCH64\|EM_ARM\|EM_X86_64"
echo "OpenHarmony native library built: $output/libmsime_host_api.so (not yet device-verified)"
