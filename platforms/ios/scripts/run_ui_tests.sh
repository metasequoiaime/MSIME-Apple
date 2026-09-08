#!/usr/bin/env bash
set -euo pipefail

project_path="${1:-build/ios/MetasequoiaImeIOS.xcworkspace}"
derived_data_path="${2:-build/ios-derived}"

if [[ ! -d "${project_path}" ]]; then
  echo "Generated Xcode project not found: ${project_path}" >&2
  exit 1
fi

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

xcodebuild \
  -workspace "${project_path}" \
  -scheme MetasequoiaImeIOS \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${test_device_id},arch=x86_64" \
  -derivedDataPath "${derived_data_path}" \
  BREW_PREFIX="$(brew --prefix)" \
  test
