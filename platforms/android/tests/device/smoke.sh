#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../../.." && pwd)
cd "$repo_root"
android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
adb="$android_sdk/platform-tools/adb"
serial=${1:-emulator-5580}
[[ "$serial" == emulator-* ]] || { echo "Only the dedicated emulator is supported" >&2; exit 1; }
avd_name=$("$adb" -s "$serial" emu avd name | tr -d '\r' | head -1)
[[ "$avd_name" == msime-client-test ]] || { echo "Refusing a non-test AVD" >&2; exit 1; }
[[ $("$adb" -s "$serial" shell getprop sys.boot_completed | tr -d '\r') == 1 ]] || { echo "Test AVD has not booted" >&2; exit 1; }
bash platforms/android/tests/device/build-editor.sh
"$adb" -s "$serial" install -r target/android/msime-client-preview.apk
"$adb" -s "$serial" install -r target/android/editor-test.apk
mkdir -p target/android/device-test
xml="$repo_root/target/android/device-test/window.xml"
dump() {
  "$adb" -s "$serial" shell uiautomator dump /data/local/tmp/msime-test-window.xml >/dev/null
  "$adb" -s "$serial" pull /data/local/tmp/msime-test-window.xml "$xml" >/dev/null 2>&1
}
tap() {
  dump
  bounds=$(xmllint --xpath "string(($1)[1]/@bounds)" "$xml")
  [[ "$bounds" =~ ^\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]$ ]] || { echo "Missing tap target: $1" >&2; exit 1; }
  "$adb" -s "$serial" shell input tap "$(( (BASH_REMATCH[1] + BASH_REMATCH[3]) / 2 ))" "$(( (BASH_REMATCH[2] + BASH_REMATCH[4]) / 2 ))"
}
"$adb" -s "$serial" shell am start -W -n app.msime.client.preview/app.msime.client.SetupActivity >/dev/null
tap '//node[@text="准备词库"]'
ready=false
for attempt in $(seq 1 30); do
  dump
  if [[ $(xmllint --xpath 'boolean(//node[contains(@text,"资源准备完成") or contains(@text,"检测到已有配置")])' "$xml") == true ]]; then ready=true; break; fi
  if [[ $(xmllint --xpath 'boolean(//node[contains(@text,"准备失败")])' "$xml") == true ]]; then echo "Device bootstrap failed" >&2; exit 1; fi
  sleep 1
done
[[ "$ready" == true ]] || { echo "Device bootstrap timed out" >&2; exit 1; }
"$adb" -s "$serial" shell ime enable app.msime.client.preview/app.msime.client.MSIMEInputService
"$adb" -s "$serial" shell ime set app.msime.client.preview/app.msime.client.MSIMEInputService
"$adb" -s "$serial" shell am force-stop app.msime.client.test
result=$("$adb" -s "$serial" shell am instrument -w app.msime.client.test/app.msime.client.test.DeviceSmoke)
printf '%s\n' "$result"
[[ "$result" == *MSIME_DEVICE_SMOKE_PASSED* ]] || { echo "System input acceptance failed" >&2; exit 1; }
result=$("$adb" -s "$serial" shell am instrument -w app.msime.client.test/app.msime.client.test.PreferencesDeviceSmoke)
printf '%s\n' "$result"
[[ "$result" == *MSIME_DEVICE_SMOKE_PASSED* ]] || { echo "Preferences acceptance failed" >&2; exit 1; }
echo "Dedicated Android AVD: install, resource setup, system input and live preferences acceptance passed"
