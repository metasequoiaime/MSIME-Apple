#!/usr/bin/env bash
set -euo pipefail

# 跳过手写就没有 Pods —— CocoaPods 在一个依赖都不剩时既不写入集成也不清除旧集成,所以那条路必须走
# xcodegen 直接生成的 .xcodeproj,不能用 workspace。
if [[ "${MSIME_IOS_SKIP_HANDWRITING:-0}" == "1" ]]; then
  default_project="build/ios/MetasequoiaImeIOS.xcodeproj"
else
  default_project="build/ios/MetasequoiaImeIOS.xcworkspace"
fi
project_path="${1:-${default_project}}"
derived_data_path="${2:-build/ios-derived}"
if [[ "${project_path}" == *.xcworkspace ]]; then
  container_flag=(-workspace "${project_path}")
else
  container_flag=(-project "${project_path}")
fi

if [[ ! -d "${project_path}" ]]; then
  echo "Generated Xcode project not found: ${project_path}" >&2
  exit 1
fi

if [[ -n "${IOS_SIMULATOR_UDID:-}" ]]; then
  test_device_id="${IOS_SIMULATOR_UDID}"
elif [[ "${MSIME_IOS_SKIP_HANDWRITING:-0}" == "1" ]]; then
  # 没有 ML Kit 就没有 x86_64 的理由,拿最新的 iPhone 跑本机架构。
  test_device_id="$(xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys

devices_by_runtime = json.load(sys.stdin)["devices"]

def version_key(runtime):
    return tuple(int(part) for part in re.findall(r"\d+", runtime))

for runtime in sorted(devices_by_runtime, key=version_key, reverse=True):
    if ".iOS-" not in runtime:
        continue
    devices = sorted(
        devices_by_runtime[runtime],
        key=lambda device: device.get("state") != "Booted",
    )
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)

raise SystemExit("No iPhone Simulator available")
')"
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
# `boot` starts the simulator and returns; the wait is in `bootstatus`, which runs after the build
# below. The build needs no simulator, so booting first lets the two spend the same minutes rather
# than consecutive ones -- coming up takes about four of them on a hosted runner.
xcrun simctl boot "${test_device_id}"

if [[ "${MSIME_IOS_SKIP_HANDWRITING:-0}" == "1" ]]; then
  destination="platform=iOS Simulator,id=${test_device_id}"
  # HandwritingTests 要 ML Kit,这条路上引擎直接回「此版本不含手写识别」。
  skip_arguments=(-skip-testing:MetasequoiaKeyboardTests/HandwritingTests)
else
  destination="platform=iOS Simulator,id=${test_device_id},arch=x86_64"
  skip_arguments=()
fi

scope_arguments=()
if [[ "${MSIME_TEST_SCOPE:-all}" == "pr" ]]; then
  # The unit suites in full, plus interface cases covering the surfaces a change is most likely to
  # break: first launch, tab navigation, the keyboard home, scheme visibility and the account tab.
  # A case is listed here for what it reaches rather than what it asserts, and the whole suite still
  # runs on every merge, so a gap costs a later signal rather than no signal.
  scope_arguments=(
    -only-testing:MetasequoiaKeyboardTests
    -only-testing:MetasequoiaServiceTests
    -only-testing:MetasequoiaImeIOSUITests/OnboardingUITests/testBrandedLaunchScreenResource
    -only-testing:MetasequoiaImeIOSUITests/OnboardingUITests/testMainTabsKeepIndependentNavigation
    -only-testing:MetasequoiaImeIOSUITests/OnboardingUITests/testKeyboardHomePrioritizesTryoutAndQuickAdjustments
    -only-testing:MetasequoiaImeIOSUITests/OnboardingUITests/testInputSchemeVisibilityPersistsAndFallsBack
    -only-testing:MetasequoiaImeIOSUITests/OnboardingUITests/testAccountEntryExplainsExplicitDataSharing
  )
elif [[ "${MSIME_TEST_SCOPE:-all}" != "all" ]]; then
  echo "Unknown MSIME_TEST_SCOPE: ${MSIME_TEST_SCOPE} (expected all or pr)" >&2
  exit 1
fi

# Build and run as two actions against one destination. A single `test` rebuilt everything the
# workflow had just built, because that build targeted `generic/platform=iOS Simulator` and this
# one targets a specific x86_64 device: different products, so nothing was reused.
#
# The scope belongs to the run rather than the build. Building every test target costs the same as
# before and keeps `test-without-building` from failing on a target the narrower build skipped.
xcodebuild \
  "${container_flag[@]}" \
  -scheme MetasequoiaImeIOS \
  -configuration Debug \
  -destination "${destination}" \
  -derivedDataPath "${derived_data_path}" \
  BREW_PREFIX="$(brew --prefix)" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing

xcrun simctl bootstatus "${test_device_id}" -b

xcodebuild \
  "${container_flag[@]}" \
  -scheme MetasequoiaImeIOS \
  -configuration Debug \
  -destination "${destination}" \
  -derivedDataPath "${derived_data_path}" \
  BREW_PREFIX="$(brew --prefix)" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ${scope_arguments[@]+"${scope_arguments[@]}"} \
  ${skip_arguments[@]+"${skip_arguments[@]}"} \
  test-without-building
