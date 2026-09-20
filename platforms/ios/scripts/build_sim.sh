#!/usr/bin/env bash
set -euo pipefail

# 模拟器这条路的入口:先生成工程,再编译或跑测试。把两步并成一条,是因为分开时第一步会被忘掉 —— 而忘掉的
# 代价不是一条清楚的错误,是 `cannot find 'X' in scope`,看着像名字写错。
#
# 每次都生成是免费的:内容没变时 xcodegen 重写出的 project.pbxproj 字节相同,Xcode 的构建系统按内容判断、
# 不认 mtime,所以零重编,只多花一秒。省这一步换不到任何东西。
#
# 这条路永远不跑 pod install,也永远不用 .xcworkspace。Apple Silicon 的模拟器上 MLKit 没有 arm64 切片,
# 必须 MSIME_IOS_SKIP_HANDWRITING=1;而那样一来 Podfile 一个依赖都不剩,CocoaPods 既不写入集成也不清除旧
# 集成,工程里就留着上一次装进去的 framework 引用,链接必然失败。详见仓库根目录的 CLAUDE.md。

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
cd "$project_root"

export MSIME_IOS_SKIP_HANDWRITING=1

simulator=${IOS_SIMULATOR_UDID:-}
if [[ -z "$simulator" ]]; then
    simulator=$(xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys

devices_by_runtime = json.load(sys.stdin)["devices"]

def version_key(runtime):
    return tuple(int(part) for part in re.findall(r"\d+", runtime))

for runtime in sorted(devices_by_runtime, key=version_key, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for device in sorted(devices_by_runtime[runtime], key=lambda d: d.get("state") != "Booted"):
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)

raise SystemExit("No iPhone Simulator available")
')
fi

# xcodegen 是先写到临时目录再搬过来的,而它不建目标的父目录。新检出的仓库里 build/ios-sim 还不存在,于是报
# 的是 `The file "XcodeGen" doesn't exist.` 加一条 /var/folders 下的路径 —— 既没说缺哪个目录,也看不出那是
# xcodegen 自己的中转目录,只会让人去查 xcodegen 装坏没有。
mkdir -p build/ios-sim
xcodegen generate --spec platforms/ios/project.yml --project build/ios-sim --project-root .

# 默认只编译。给参数就原样传给 xcodebuild,所以跑测试是
#   platforms/ios/scripts/build_sim.sh -only-testing:MetasequoiaKeyboardTests test
action=("$@")
if [[ ${#action[@]} -eq 0 ]]; then
    action=(build)
fi

exec xcodebuild \
    -project build/ios-sim/MetasequoiaImeIOS.xcodeproj \
    -scheme MetasequoiaImeIOS \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath build/ios-sim/DerivedData \
    "${action[@]}"
