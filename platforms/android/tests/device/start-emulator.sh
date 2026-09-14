#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$repo_root"
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
[[ -f "$android_sdk/system-images/android-35/default/arm64-v8a/package.xml" ]] || {
  echo "Install system-images;android-35;default;arm64-v8a in the selected SDK first" >&2; exit 1;
}
existing=$("$android_sdk/platform-tools/adb" -s emulator-5580 emu avd name 2>/dev/null | tr -d '\r' | head -1 || true)
if [[ -n "$existing" ]]; then
  [[ "$existing" == msime-client-test ]] || { echo "Port 5580 belongs to another AVD" >&2; exit 1; }
  echo "Dedicated AVD is already live at emulator-5580"; exit 0
fi
avd_home="$repo_root/target/android/avd-home"
mkdir -p "$avd_home"
if [[ ! -f "$avd_home/msime-client-test.ini" ]]; then
  # avdmanager canonicalizes toolsdir; a Homebrew symlink otherwise selects the
  # Homebrew prefix instead of the SDK containing the downloaded image.
  tools_marker="$android_sdk/cmdline-tools/msime-avd-test"
  mkdir -p "$tools_marker"
  printf 'no\n' | ANDROID_AVD_HOME="$avd_home" \
    AVDMANAGER_OPTS="-Dcom.android.sdkmanager.toolsdir=\"$tools_marker\"" \
    "$android_sdk/cmdline-tools/latest/bin/avdmanager" create avd --name msime-client-test \
      --package 'system-images;android-35;default;arm64-v8a' --path "$avd_home/msime-client-test.avd" --device pixel_6
fi
exec env ANDROID_HOME="$android_sdk" ANDROID_AVD_HOME="$avd_home" \
  "$android_sdk/emulator/emulator" -avd msime-client-test -port 5580 \
  -no-window -no-audio -no-snapshot -no-metrics -gpu swiftshader -memory 2560
