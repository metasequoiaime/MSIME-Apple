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

# 跑测试的时候只留两台模拟器,但克隆的模板必须是已经完成过首次启动的那一台。这两件事看着矛盾,实际是先后:
# 启动它、等它真的起来、然后在 xcodebuild 之前关掉。
#
# 为什么不能常驻:Xcode 并行跑的是克隆,它自己创建、自己启动,那台被选中的设备一条用例都不跑,留着就是多一台
# iOS 占内存。实测日志里三台同时活着(原始 + Clone 1 + Clone 2),而所有用例都落在两个克隆上 —— 这就是
# KeyboardSurfaceUITests 整类一起倒的由来:失败清一色是
#   Failed to get background assertion for target app with pid …: Timed out while acquiring…
# 一条断言都没有,而 Xcode 是按类把用例分给克隆的,所以一台克隆被系统回收就带走一整类。把并行数从 4 调到 2
# 只是把五台变成三台,频率降了没有消失。
#
# 为什么又不能干脆不启动:那是上一版的做法,理由是「克隆不要求源设备已启动」—— 这句话本身没错,关机状态下
# xcodebuild 照样克隆并启动。漏掉的是预启动在并行路径上还兼着第二个作用:把克隆的模板烤热。托管 runner 上的
# 那台设备从来没有启动过,克隆继承的就是一台没走完首次启动的机器,于是首次启动的代价落到每一台克隆头上,落在
# 一台已经在跑测试的机器上。代价是一种新的红,和上面那种不一样:
#   DTServiceHub - Error resuming pid …: Failed to send signal 19 to process …: 3
#   IDERunOperationFailingWorker = IDELaunchiPhoneSimulatorLauncher
# 一条断言都没有,时间落在 test-without-building 之后七分半 —— 正好是克隆创建加首次启动,拉起 app 时进程已经
# 不在了。这句报错在此之前的任何一次运行里都没出现过。
parallel_scope=false
if [[ "${MSIME_TEST_SCOPE:-all}" == "all" ]]; then
  parallel_scope=true
fi

# 先关一次:陈旧的已启动设备会在应用安装服务卡死时照常回应状态查询,而关机清掉那个状态。
xcrun simctl shutdown "${test_device_id}" >/dev/null 2>&1 || true
# `boot` 启动后立即返回,等待在后面的 bootstatus 里 —— 构建不需要模拟器,所以先启动能让两者共用同一段时间,
# 而不是一前一后;在托管 runner 上它要花四分钟左右。
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

# 全量分片:两台 runner 各跑一半,墙钟减半而一条用例都不少。不设分片就是整套,本机就该这么跑。
#
# 切在哪里是量出来的,不是猜的。一次跑完的全量里,185 条用例合计 2624 秒,其中界面那四类占 2433 秒:
#   SettingsUITests 743.8s / SkinUITests 706.6s / KeyboardSurfaceUITests 691.2s / WelcomeUITests 291.8s
# 剩下二十多个单元类加起来 191 秒。所以最肥的两类单独一片(1451 秒),其余一片(1173 秒),两边差不多齐。
#
# Xcode 是按类把用例分给克隆的,分片也按类分 —— 同一个单位,不会有哪一条被切成两半或漏掉。
shard_arguments=()
case "${MSIME_TEST_SHARD:-}" in
  "") ;;
  heavy)
    for heavy_class in MetasequoiaImeIOSUITests/SettingsUITests MetasequoiaImeIOSUITests/SkinUITests; do
      shard_arguments+=(-only-testing:"${heavy_class}")
    done
    ;;
  rest)
    for heavy_class in MetasequoiaImeIOSUITests/SettingsUITests MetasequoiaImeIOSUITests/SkinUITests; do
      shard_arguments+=(-skip-testing:"${heavy_class}")
    done
    ;;
  *)
    echo "Unknown MSIME_TEST_SHARD: ${MSIME_TEST_SHARD} (expected heavy or rest)" >&2
    exit 1
    ;;
esac
if [[ -n "${MSIME_TEST_SHARD:-}" && "${MSIME_TEST_SCOPE:-all}" != "all" ]]; then
  echo "MSIME_TEST_SHARD only divides the full suite; scope is ${MSIME_TEST_SCOPE}" >&2
  exit 1
fi

# The interface cases are a cold launch and a walk through the app each, so they are bound by the
# Simulator rather than the machine: running them one at a time leaves most of a multi-core runner
# idle. Cloning the Simulator and running test classes across the clones is what that idleness is
# for. Only where there is a suite worth spreading -- the handwriting scope is three cases, and the
# clones would cost more to boot than the cases take to run.
#
# 两个克隆,不是四个。四个时这一套在 CI 上反复整片倒下,失败信息全是同一句
#   Failed to get background assertion for target app with pid …: Timed out while acquiring background assertion.
# 一条断言失败都没有 —— 那是 runner 扛不住四台模拟器同时冷启动,SpringBoard 给不出后台断言,而它看起来
# 像是测试挂了。一次八条、一次五条,重跑照旧。
#
# 慢一些是有意换的:这一套现在 33 到 40 分钟,步骤上限是 60,装得下。一次假红要人来判断它是不是真的,
# 那比多出来的几分钟贵得多,而它挡的是发布。
parallel_arguments=()
if [[ "${MSIME_TEST_SCOPE:-all}" == "all" ]]; then
  parallel_arguments=(
    -parallel-testing-enabled YES
    -maximum-concurrent-test-simulator-destinations "${MSIME_IOS_PARALLEL_SIMULATORS:-2}"
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
if [[ "$parallel_scope" == true ]]; then
  # 模板已经烤热,这台自己一条用例都不跑。关掉它,测试期间就只有两台克隆活着。
  xcrun simctl shutdown "${test_device_id}"
fi

xcodebuild \
  "${container_flag[@]}" \
  -scheme MetasequoiaImeIOS \
  -configuration Debug \
  -destination "${destination}" \
  -derivedDataPath "${derived_data_path}" \
  BREW_PREFIX="$(brew --prefix)" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ${scope_arguments[@]+"${scope_arguments[@]}"} \
  ${shard_arguments[@]+"${shard_arguments[@]}"} \
  ${skip_arguments[@]+"${skip_arguments[@]}"} \
  ${parallel_arguments[@]+"${parallel_arguments[@]}"} \
  test-without-building
