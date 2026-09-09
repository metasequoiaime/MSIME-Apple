#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [[ -z "$android_sdk" ]]; then
  echo "Set ANDROID_SDK_ROOT to an installed Android SDK" >&2
  exit 1
fi
android_jar="$android_sdk/platforms/android-35/android.jar"
if [[ ! -f "$android_jar" ]]; then
  echo "Android API 35 platform is required" >&2
  exit 1
fi
output_dir=$(mktemp -d)
trap 'rm -f "$output_dir/manifest.apk" "$output_dir/resources.zip"; find "$output_dir" -name "*.class" -delete; find "$output_dir" -depth -type d -empty -delete' EXIT
javac --release 17 -Xlint:all -Werror -cp "$android_jar" -d "$output_dir" \
  "$repo_root"/platforms/android/java/app/msime/client/*.java \
  "$repo_root/platforms/android/tests/EditorSmoke.java" \
  "$repo_root/platforms/android/tests/PreferencesSmoke.java"
java -cp "$output_dir" EditorSmoke
java -cp "$output_dir" PreferencesSmoke
"$android_sdk/build-tools/35.0.0/aapt2" compile --dir "$repo_root/platforms/android/res" -o "$output_dir/resources.zip"
"$android_sdk/build-tools/35.0.0/aapt2" link -I "$android_jar" \
  --manifest "$repo_root/platforms/android/AndroidManifest.xml" \
  -o "$output_dir/manifest.apk" "$output_dir/resources.zip"
echo "Android service Java/API and manifest/resource checks passed; no installable/native APK produced"
