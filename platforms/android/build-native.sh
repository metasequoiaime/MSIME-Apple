#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
abi=${1:-arm64-v8a}
case "$abi" in
  arm64-v8a) rust_target=aarch64-linux-android; compiler_target=aarch64-linux-android; triplet=arm64-msime-android; cargo_linker=CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER ;;
  x86_64) rust_target=x86_64-linux-android; compiler_target=x86_64-linux-android; triplet=x64-msime-android; cargo_linker=CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER ;;
  *) echo "Supported ABIs: arm64-v8a, x86_64" >&2; exit 1 ;;
esac
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
ndk=${MSIME_ANDROID_NDK:-${android_sdk}/ndk/28.2.13676358}
vcpkg_root=${MSIME_VCPKG_ROOT:-$repo_root/target/tooling/vcpkg}
if [[ ! -f "$ndk/source.properties" ]] || ! grep -q '28.2.13676358' "$ndk/source.properties"; then
  echo "Install pinned NDK 28.2.13676358 and set ANDROID_SDK_ROOT or MSIME_ANDROID_NDK" >&2; exit 1
fi
if [[ ! -x "$vcpkg_root/vcpkg" ]] || [[ $(git -C "$vcpkg_root" rev-parse HEAD) != ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0 ]]; then
  echo "Provide bootstrapped vcpkg at pinned commit ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0 using MSIME_VCPKG_ROOT" >&2; exit 1
fi
case $(uname -s) in
  Darwin) host_tag=darwin-x86_64 ;;
  Linux) host_tag=linux-x86_64 ;;
  *) echo "Use this build script on macOS or Linux" >&2; exit 1 ;;
esac
toolchain="$ndk/toolchains/llvm/prebuilt/$host_tag"
compiler="$toolchain/bin/${compiler_target}28-clang"
# vcpkg manifest installs reconcile their root: keep ABIs separate so one build
# cannot uninstall the other ABI's dependencies.
deps="$repo_root/target/android-deps/$abi"
ANDROID_NDK_HOME="$ndk" VCPKG_DISABLE_METRICS=1 "$vcpkg_root/vcpkg" install \
  --x-manifest-root="$repo_root/platforms/android" --x-install-root="$deps" \
  --overlay-triplets="$repo_root/platforms/android/triplets" --triplet="$triplet"
env "CC_${rust_target//-/_}=$compiler" "CXX_${rust_target//-/_}=$compiler++" \
  "AR_${rust_target//-/_}=$toolchain/bin/llvm-ar" "$cargo_linker=$compiler" \
  MSIME_ANDROID_NDK="$ndk" MSIME_ANDROID_DEPS="$deps/$triplet" \
  CARGO_TARGET_DIR="$repo_root/target/android-cargo" \
  RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384" \
  cargo build -p msime-host-api --target "$rust_target" --release --locked
output="$repo_root/target/android/jniLibs/$abi"
mkdir -p "$output"
cp "$repo_root/target/android-cargo/$rust_target/release/libmsime_host_api.so" "$output/"
cp "$toolchain/sysroot/usr/lib/$compiler_target/libc++_shared.so" "$output/"
"$compiler++" -std=c++17 -shared -fPIC -Wall -Wextra -Werror \
  -Wl,--no-undefined -Wl,-z,max-page-size=16384 -Wl,-soname,libmsime_android.so \
  platforms/android/native/client_jni.cpp -Icrates/host-api/include \
  -L"$output" -lmsime_host_api -o "$output/libmsime_android.so"
bash platforms/android/verify-native.sh "$toolchain/bin/llvm-readelf" "$output" "$abi"
notices="$repo_root/target/android/notices/$abi"
mkdir -p "$notices"
for copyright_file in "$deps/$triplet"/share/*/copyright; do
  package=$(basename "$(dirname "$copyright_file")")
  cp "$copyright_file" "$notices/$package.txt"
done
cp "$toolchain/NOTICE" "$notices/ndk-toolchain.txt"
cp "$toolchain/sysroot/NOTICE" "$notices/ndk-sysroot.txt"
echo "Android native libraries built: $output (not yet device-verified)"
