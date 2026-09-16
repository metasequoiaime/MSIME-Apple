#!/usr/bin/env bash
set -euo pipefail

# HandwritingTests 里唯一需要 ML Kit 的三个用例:它们拿真实笔迹断言引擎认出哪个字。SDK 的 arm64 切片是给真机的,模拟器上没有可链接的切片,所以只有 Intel runner 跑得了它们。
#
# 同一个类里其余用例是纯 UIKit —— hitTest、布局高度、笔画增删 —— 一行识别都不碰。它们原先跟着整类一起被跳过,于是只在合并后的 Intel job 里露面:2.5 秒的东西压在二十多分钟的 Intel 构建后面,而 PR 上一点覆盖都没有,包括那条「整块面板写不了字」的回归用例。现在按用例分,不按类分。
#
# 这个数组是那条界线的唯一一处定义:arm64 拿它做 -skip-testing,Intel 拿它做 -only-testing,所以两边不会各自漂移。
recognition_cases=(
  MetasequoiaKeyboardTests/HandwritingTests/testRealChineseInkRecognition
  MetasequoiaKeyboardTests/HandwritingTests/testCommonCharactersFromPenTrajectories
  MetasequoiaKeyboardTests/HandwritingTests/testCandidateSelectionInsertsOnlyAfterConfirmation
)

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
  # 没有 ML Kit,引擎对这三个直接回「此版本不含手写识别」。同类里其余用例不碰识别,照跑。
  skip_arguments=()
  for recognition_case in "${recognition_cases[@]}"; do
    skip_arguments+=(-skip-testing:"${recognition_case}")
  done
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
    -only-testing:MetasequoiaImeIOSUITests/WelcomeUITests/testBrandedLaunchScreenResource
    -only-testing:MetasequoiaImeIOSUITests/WelcomeUITests/testMainTabsKeepIndependentNavigation
    -only-testing:MetasequoiaImeIOSUITests/KeyboardSurfaceUITests/testKeyboardHomePrioritizesTryoutAndQuickAdjustments
    -only-testing:MetasequoiaImeIOSUITests/SettingsUITests/testInputSchemeVisibilityPersistsAndFallsBack
    -only-testing:MetasequoiaImeIOSUITests/WelcomeUITests/testAccountEntryExplainsExplicitDataSharing
  )
elif [[ "${MSIME_TEST_SCOPE:-all}" == "handwriting" ]]; then
  # 只有这三个用例需要 ML Kit,也就只有它们需要 Intel runner。别的一概不在这里建、不在这里跑:界面套件不依赖 ML Kit,属于 arm64,不该跟一个二十多分钟的 Intel 构建抢同一个 job 的分钟数。
  scope_arguments=()
  for recognition_case in "${recognition_cases[@]}"; do
    scope_arguments+=(-only-testing:"${recognition_case}")
  done
elif [[ "${MSIME_TEST_SCOPE:-all}" != "all" ]]; then
  echo "Unknown MSIME_TEST_SCOPE: ${MSIME_TEST_SCOPE} (expected all, pr or handwriting)" >&2
  exit 1
fi

# The interface cases are a cold launch and a walk through the app each, so they are bound by the
# Simulator rather than the machine: running them one at a time leaves most of a multi-core runner
# idle. Cloning the Simulator and running test classes across the clones is what that idleness is
# for. Only where there is a suite worth spreading -- the handwriting scope is three cases, and the
# clones would cost more to boot than the cases take to run.
parallel_arguments=()
if [[ "${MSIME_TEST_SCOPE:-all}" == "all" ]]; then
  parallel_arguments=(
    -parallel-testing-enabled YES
    -maximum-concurrent-test-simulator-destinations "${MSIME_IOS_PARALLEL_SIMULATORS:-4}"
  )
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
  ${parallel_arguments[@]+"${parallel_arguments[@]}"} \
  test-without-building
