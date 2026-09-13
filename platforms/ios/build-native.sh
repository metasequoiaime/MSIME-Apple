#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
variant=${1:-device}
case "$variant" in
  device) rust_target=aarch64-apple-ios; sdk=iphoneos ;;
  simulator) rust_target=aarch64-apple-ios-sim; sdk=iphonesimulator ;;
  *) echo "Usage: $0 [device|simulator]" >&2; exit 2 ;;
esac

if ! rustup target list --installed | grep -qx "$rust_target"; then
  echo "Install Rust target first: rustup target add $rust_target" >&2
  exit 1
fi
linker=$(xcrun --sdk "$sdk" --find clang)
deployment_target=${IPHONEOS_DEPLOYMENT_TARGET:-16.0}
deps_prefix=${MSIME_IOS_DEPS:-}
if [[ -z "$deps_prefix" || ! -d "$deps_prefix" ]]; then
  echo "Set MSIME_IOS_DEPS to an iOS-compatible dependency prefix containing Boost" >&2
  exit 1
fi
boost_dir=${MSIME_BOOST_DIR:-}
if [[ -z "$boost_dir" ]]; then
  shopt -s nullglob
  boost_configs=(
    "$deps_prefix"/lib/cmake/Boost-*/BoostConfig.cmake
    "$deps_prefix"/lib64/cmake/Boost-*/BoostConfig.cmake
  )
  shopt -u nullglob
  if (( ${#boost_configs[@]} == 1 )); then
    boost_dir=$(dirname "${boost_configs[0]}")
  elif (( ${#boost_configs[@]} > 1 )); then
    echo "Multiple BoostConfig.cmake files found; set MSIME_BOOST_DIR explicitly" >&2
    exit 1
  fi
fi
if [[ -n "$boost_dir" && ! -f "$boost_dir/BoostConfig.cmake" && ! -f "$boost_dir/boost-config.cmake" ]]; then
  echo "MSIME_BOOST_DIR must contain BoostConfig.cmake" >&2
  exit 1
fi
boost_headers_dir=${MSIME_BOOST_HEADERS_DIR:-}
if [[ -z "$boost_headers_dir" ]]; then
  shopt -s nullglob
  boost_headers_configs=(
    "$deps_prefix"/lib/cmake/boost_headers-*/boost_headers-config.cmake
    "$deps_prefix"/lib64/cmake/boost_headers-*/boost_headers-config.cmake
  )
  shopt -u nullglob
  if (( ${#boost_headers_configs[@]} == 1 )); then
    boost_headers_dir=$(dirname "${boost_headers_configs[0]}")
  elif (( ${#boost_headers_configs[@]} > 1 )); then
    echo "Multiple boost_headers config files found; set MSIME_BOOST_HEADERS_DIR explicitly" >&2
    exit 1
  fi
fi
if [[ -n "$boost_headers_dir" && ! -f "$boost_headers_dir/boost_headers-config.cmake" ]]; then
  echo "MSIME_BOOST_HEADERS_DIR must contain boost_headers-config.cmake" >&2
  exit 1
fi
if [[ -n "$boost_dir" ]]; then
  export MSIME_BOOST_DIR="$boost_dir"
else
  unset MSIME_BOOST_DIR
fi
if [[ -n "$boost_headers_dir" ]]; then
  export MSIME_BOOST_HEADERS_DIR="$boost_headers_dir"
else
  unset MSIME_BOOST_HEADERS_DIR
fi
target_dir="$repo_root/target/ios-cargo/$variant"
output_dir="$repo_root/target/ios/$variant"
mkdir -p "$output_dir"
linker_var="CARGO_TARGET_$(printf '%s' "$rust_target" | tr '[:lower:]-' '[:upper:]_')_LINKER"

env "$linker_var=$linker" \
  IPHONEOS_DEPLOYMENT_TARGET="$deployment_target" \
  CMAKE_PREFIX_PATH="$deps_prefix" \
  CARGO_TARGET_DIR="$target_dir" \
  cargo build -p msime-host-api --target "$rust_target" --release --locked
cp "$target_dir/$rust_target/release/libmsime_host_api.a" "$output_dir/libmsime_host_api.a"
echo "iOS host library built: $output_dir/libmsime_host_api.a"
