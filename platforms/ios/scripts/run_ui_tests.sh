#!/usr/bin/env bash
set -euo pipefail

project_path="${1:-build/ios/MetasequoiaImeIOS.xcworkspace}"
derived_data_path="${2:-build/ios-derived}"

# all: every target. unit: everything except the interface suite. ui: the interface suite alone,
# optionally split into MSIME_UI_SHARD_COUNT slices so CI can run them on parallel runners.
test_scope="${MSIME_TEST_SCOPE:-all}"
ui_shard_index="${MSIME_UI_SHARD_INDEX:-1}"
ui_shard_count="${MSIME_UI_SHARD_COUNT:-1}"
ui_target="MetasequoiaImeIOSUITests"

if [[ ! -d "${project_path}" ]]; then
  echo "Generated Xcode project not found: ${project_path}" >&2
  exit 1
fi

case "${test_scope}" in
  all | unit | ui) ;;
  *)
    echo "Unknown MSIME_TEST_SCOPE: ${test_scope} (expected all, unit or ui)" >&2
    exit 1
    ;;
esac

if [[ -n "${IOS_SIMULATOR_UDID:-}" ]]; then
  test_device_id="${IOS_SIMULATOR_UDID}"
else
  test_device_id="$(xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys
import subprocess

devices_by_runtime = json.load(sys.stdin)["devices"]
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "runtime", "list", "-j"]))
compatible = {r["runtimeIdentifier"] for r in runtimes.values()
              if "x86_64" in r.get("supportedArchitectures", [])}

def version_key(runtime):
    return tuple(int(part) for part in re.findall(r"\d+", runtime))

for runtime in sorted(devices_by_runtime, key=version_key, reverse=True):
    if ".iOS-" not in runtime or runtime not in compatible:
        continue
    devices = sorted(
        devices_by_runtime[runtime],
        key=lambda device: device.get("state") != "Booted",
    )
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)

raise SystemExit("No x86_64-compatible iPhone Simulator found; install a universal iOS runtime")
')"
fi

# A stale booted runner can accept status requests while its app installation service is wedged.
# Restarting the selected device is bounded by bootstatus and preserves its installed data.
xcrun simctl shutdown "${test_device_id}" >/dev/null 2>&1 || true
xcrun simctl boot "${test_device_id}"
xcrun simctl bootstatus "${test_device_id}" -b

xcodebuild_common=(
  -workspace "${project_path}"
  -scheme MetasequoiaImeIOS
  -configuration Debug
  -destination "platform=iOS Simulator,id=${test_device_id},arch=x86_64"
  -derivedDataPath "${derived_data_path}"
  BREW_PREFIX="$(brew --prefix)"
)

if [[ "${test_scope}" == "all" ]]; then
  xcodebuild "${xcodebuild_common[@]}" test
  exit 0
fi

if [[ "${test_scope}" == "unit" ]]; then
  xcodebuild "${xcodebuild_common[@]}" -skip-testing:"${ui_target}" test
  exit 0
fi

if [[ "${ui_shard_count}" -le 1 ]]; then
  xcodebuild "${xcodebuild_common[@]}" -only-testing:"${ui_target}" test
  exit 0
fi

# Splitting by class would not help: the interface suite is one class, and xcodebuild distributes
# parallel work per class. Enumerate the cases instead and deal them out one runner at a time, so a
# new test joins a slice without anyone editing the workflow.
xcodebuild "${xcodebuild_common[@]}" build-for-testing

enumerated="${derived_data_path}/ui-test-enumeration.json"
mkdir -p "${derived_data_path}"
# Write to a file rather than standard out: xcodebuild interleaves its own progress into the
# stream and corrupts the document.
xcodebuild "${xcodebuild_common[@]}" \
  -only-testing:"${ui_target}" \
  -enumerate-tests \
  -test-enumeration-style flat \
  -test-enumeration-format json \
  -test-enumeration-output-path "${enumerated}" \
  test-without-building

# macOS still ships bash 3.2, which has no mapfile.
shard_arguments=()
while IFS= read -r argument; do
  shard_arguments+=("${argument}")
done < <(
  MSIME_UI_SHARD_INDEX="${ui_shard_index}" \
  MSIME_UI_SHARD_COUNT="${ui_shard_count}" \
  python3 "$(dirname "$0")/select_ui_test_shard.py" "${enumerated}"
)

echo "Interface slice ${ui_shard_index}/${ui_shard_count}: ${#shard_arguments[@]} cases"
xcodebuild "${xcodebuild_common[@]}" "${shard_arguments[@]}" test-without-building
