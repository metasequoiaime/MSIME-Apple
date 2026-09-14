#!/usr/bin/env bash
# Tauri management UI and the native IME share one package and private state.
set -euo pipefail
umask 077
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
resource_dir=${1:?usage: build-client-apk.sh <verified-resource-directory> [arm64-v8a|x86_64]}
abi=${2:-arm64-v8a}
case "$abi" in
  arm64-v8a) tauri_target=aarch64; dependency_triplet=arm64-msime-android ;;
  x86_64) tauri_target=x86_64; dependency_triplet=x64-msime-android ;;
  *) echo "Unsupported ABI" >&2; exit 1 ;;
esac
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
[[ -n "$android_sdk" ]] || { echo "Android SDK required" >&2; exit 1; }
[[ -f "$android_sdk/platforms/android-36/android.jar" && -x "$android_sdk/build-tools/35.0.0/apksigner" ]] || { echo "Android API 36 and build-tools 35 required" >&2; exit 1; }
android_ndk=${MSIME_ANDROID_NDK:-$android_sdk/ndk/28.2.13676358}
android_dependencies="$repo_root/target/android-deps/$abi/$dependency_triplet"
artifacts=$(cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$resource_dir")
bash platforms/android/build-native.sh "$abi"
tauri_jni="$repo_root/target/android/tauri-jniLibs/$abi"
mkdir -p "$tauri_jni"
cp "$repo_root/target/android/jniLibs/$abi/libmsime_android.so" \
  "$repo_root/target/android/jniLibs/$abi/libmsime_host_api.so" "$tauri_jni/"
assets="$repo_root/target/android/tauri-assets"
mkdir -p "$assets/dictionary"
cp resources/desktop-dictionary.lock.json "$assets/"
while IFS= read -r artifact; do cp "$resource_dir/$artifact" "$assets/dictionary/"; done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$assets/dictionary" >/dev/null
mkdir -p "$assets/native-notices"
cp -R target/android/notices/. "$assets/native-notices/"
cp LICENSE "$assets/client-LICENSE.txt"
ANDROID_HOME="$android_sdk" NDK_HOME="$android_ndk" MSIME_ANDROID_NDK="$android_ndk" \
  MSIME_ANDROID_DEPS="$android_dependencies" \
  pnpm --filter @msime/desktop tauri android build --apk --target "$tauri_target" --ci
unsigned="$repo_root/apps/desktop/src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release-unsigned.apk"
[[ -f "$unsigned" ]] || { echo "Expected Tauri APK not produced" >&2; exit 1; }
keystore="$repo_root/target/android/development.keystore"
if [[ ! -f "$keystore" ]]; then
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=MSIME Development" -keyalg RSA -keysize 2048 -validity 3650
fi
output="$repo_root/target/android/msime-client-preview.apk"
"$android_sdk/build-tools/35.0.0/apksigner" sign --ks "$keystore" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android --out "$output" "$unsigned"
"$android_sdk/build-tools/35.0.0/apksigner" verify "$output"
"$android_sdk/build-tools/35.0.0/zipalign" -c -P 16 4 "$output"
echo "Tauri + native IME development APK built for $abi; no device changed"
