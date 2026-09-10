#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
variant=${1:-device}
case "$variant" in
  device) rust_target=aarch64-apple-ios; sdk=iphoneos; arch=arm64 ;;
  simulator) rust_target=aarch64-apple-ios-sim; sdk=iphonesimulator; arch=arm64 ;;
  *) echo "Usage: $0 [device|simulator]" >&2; exit 2 ;;
esac

if ! rustup target list --installed | grep -qx "$rust_target"; then
  echo "Install Rust target first: rustup target add $rust_target" >&2
  exit 1
fi
sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
linker=$(xcrun --sdk "$sdk" --find clang)
deployment_target=${IPHONEOS_DEPLOYMENT_TARGET:-16.0}
deps_prefix=${MSIME_IOS_DEPS:-}
if [[ -z "$deps_prefix" || ! -d "$deps_prefix" ]]; then
  echo "Set MSIME_IOS_DEPS to an iOS-compatible dependency prefix containing Boost" >&2
  exit 1
fi
target_dir="$repo_root/target/ios-cargo/$variant"
output_dir="$repo_root/target/ios/$variant"
mkdir -p "$output_dir"
linker_var="CARGO_TARGET_$(printf '%s' "$rust_target" | tr '[:lower:]-' '[:upper:]_')_LINKER"

env "$linker_var=$linker" \
  MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
  CMAKE_PREFIX_PATH="$deps_prefix" \
  CARGO_TARGET_DIR="$target_dir" \
  RUSTFLAGS="-C link-arg=-isysroot -C link-arg=$sdk_path -C link-arg=-mios-version-min=$deployment_target" \
  cargo build -p msime-host-api --target "$rust_target" --release --locked
cp "$target_dir/$rust_target/release/libmsime_host_api.a" "$output_dir/libmsime_host_api.a"
echo "iOS host library built: $output_dir/libmsime_host_api.a"
