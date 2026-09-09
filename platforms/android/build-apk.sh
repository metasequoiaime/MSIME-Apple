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
mkdir -p target/android
build_dir=$(mktemp -d "$repo_root/target/android/apk-build.XXXXXX")
mkdir -p "$build_dir/classes" "$build_dir/dex" "$build_dir/assets/dictionary" "$build_dir/pack/lib"
cp resources/desktop-dictionary.lock.json "$build_dir/assets/"
while IFS= read -r artifact; do cp "$resource_dir/$artifact" "$build_dir/assets/dictionary/"; done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$build_dir/assets/dictionary" >/dev/null
cp -R target/android/notices "$build_dir/assets/native-notices"
cp LICENSE "$build_dir/assets/client-LICENSE.txt"
javac --release 17 -Xlint:all -Werror -cp "$android_jar" -d "$build_dir/classes" platforms/android/java/app/msime/client/*.java
jar --create --file "$build_dir/classes.jar" -C "$build_dir/classes" .
"$tools_dir/d8" --release --min-api 28 --lib "$android_jar" --output "$build_dir/dex" "$build_dir/classes.jar"
"$tools_dir/aapt2" compile --dir platforms/android/res -o "$build_dir/resources.zip"
"$tools_dir/aapt2" link -I "$android_jar" --manifest platforms/android/AndroidManifest.xml \
  -A "$build_dir/assets" -o "$build_dir/unsigned.apk" "$build_dir/resources.zip"
cp "$build_dir/dex/classes.dex" "$build_dir/pack/"
for abi in arm64-v8a x86_64; do cp -R "target/android/jniLibs/$abi" "$build_dir/pack/lib/"; done
(cd "$build_dir/pack" && zip -q -0 -r "$build_dir/unsigned.apk" lib classes.dex)
"$tools_dir/zipalign" -P 16 4 "$build_dir/unsigned.apk" "$build_dir/aligned.apk"
keystore="$repo_root/target/android/development.keystore"
if [[ ! -f "$keystore" ]]; then
  keytool -genkeypair -keystore "$keystore" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=MSIME Development" -keyalg RSA -keysize 2048 -validity 3650
fi
"$tools_dir/apksigner" sign --ks "$keystore" --ks-key-alias androiddebugkey \
  --ks-pass pass:android --key-pass pass:android --out "$build_dir/signed.apk" "$build_dir/aligned.apk"
"$tools_dir/apksigner" verify --verbose "$build_dir/signed.apk"
"$tools_dir/zipalign" -c -P 16 4 "$build_dir/signed.apk"
cp "$build_dir/signed.apk" target/android/msime-client-preview.apk
echo "Development APK built: $repo_root/target/android/msime-client-preview.apk; not installed or device-verified"
