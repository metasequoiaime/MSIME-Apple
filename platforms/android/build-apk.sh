#!/usr/bin/env bash
set -euo pipefail
umask 077
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
resource_dir=${1:?usage: build-apk.sh <verified-resource-directory>}
resource_dir=$(cd "$resource_dir" && pwd)
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
tools_dir="$android_sdk/build-tools/35.0.0"
android_jar="$android_sdk/platforms/android-35/android.jar"
[[ -f "$android_jar" && -x "$tools_dir/d8" ]] || { echo "Android platform/build-tools 35 required" >&2; exit 1; }
artifacts=$(cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$resource_dir")
for abi in arm64-v8a x86_64; do bash platforms/android/build-native.sh "$abi"; done

# The host is a Gradle build now: it uses AndroidX and Material, and those ship as AARs whose
# resources have to be merged and whose R classes have to be generated per package. The previous
# aapt2/d8 pipeline had no dependency resolution at all, so every one of those steps would have been
# hand-rolled here. Gradle and AGP are pinned to the versions the Tauri bundle already resolves.
assets="$repo_root/target/android/host-assets"
rm -rf "$assets"
mkdir -p "$assets/dictionary"
cp resources/desktop-dictionary.lock.json "$assets/"
while IFS= read -r artifact; do cp "$resource_dir/$artifact" "$assets/dictionary/"; done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$assets/dictionary" >/dev/null
mkdir -p "$assets/native-notices"
cp -R target/android/notices/. "$assets/native-notices/"
cp LICENSE "$assets/client-LICENSE.txt"

gradle_dir="$repo_root/platforms/android/gradle-app"
tauri_gradlew="$repo_root/apps/desktop/src-tauri/gen/android/gradlew"
[[ -x "$tauri_gradlew" ]] || { echo "Gradle wrapper required; run the Tauri Android init once" >&2; exit 1; }
ANDROID_HOME="$android_sdk" "$tauri_gradlew" --project-dir "$gradle_dir" --console=plain assembleRelease

unsigned="$gradle_dir/app/build/outputs/apk/release/app-release-unsigned.apk"
[[ -f "$unsigned" ]] || { echo "Expected host APK not produced" >&2; exit 1; }
keystore="$repo_root/target/android/development.keystore"
if [[ ! -f "$keystore" ]]; then
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=MSIME Development" -keyalg RSA -keysize 2048 -validity 3650
fi
"$tools_dir/zipalign" -P 16 4 "$unsigned" "$repo_root/target/android/aligned.apk"
"$tools_dir/apksigner" sign --ks "$keystore" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android \
  --out target/android/msime-client-preview.apk "$repo_root/target/android/aligned.apk"
"$tools_dir/apksigner" verify --verbose target/android/msime-client-preview.apk
"$tools_dir/zipalign" -c -P 16 4 target/android/msime-client-preview.apk
rm -f "$repo_root/target/android/aligned.apk"
echo "Development APK built: $repo_root/target/android/msime-client-preview.apk; not installed or device-verified"
