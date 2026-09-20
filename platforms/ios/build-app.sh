#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
resource_dir=${1:?usage: build-app.sh <verified-resource-directory> [device|simulator]}
variant=${2:-simulator}
case "$variant" in
  device) tauri_target=aarch64 ;;
  simulator) tauri_target=aarch64-sim ;;
  *) echo "Unsupported iOS variant: $variant" >&2; exit 2 ;;
esac

bash "$repo_root/platforms/ios/stage-resources.sh" "$resource_dir"
bash "$repo_root/platforms/ios/build-native.sh" "$variant"

# iOS 的产品本体是 platforms/ios 下的原生宿主 MSIMEClientApp：装机、启动、被系统识别为输入法的都是它，所以它是这个脚本的默认产物。Tauri/React 是它承载的公共组件，不是 iOS 的产品本体；只在需要单独构建那部分时用 MSIME_IOS_TAURI_COMPONENT=1 显式选择，不拿它作为 iOS 的产品去启动或验收。
if [ "${MSIME_IOS_TAURI_COMPONENT:-0}" = 1 ]; then
  if [ "$variant" = device ]; then
    command -v pod >/dev/null || { echo "CocoaPods is required for the device handwriting build" >&2; exit 1; }
    (cd "$repo_root/apps/desktop/src-tauri/gen/apple" && pod install --deployment)
  fi
  (cd "$repo_root" && pnpm --filter @msime/desktop tauri ios build \
    --target "$tauri_target" --no-sign --ci)
  exit 0
fi

sdk=$([ "$variant" = device ] && echo iphoneos || echo iphonesimulator)
(cd "$repo_root/platforms/ios" && xcodegen generate -s project.yml -p .)
build_container=(-project "$repo_root/platforms/ios/MSIMEClient.xcodeproj")
if [ "$variant" = device ]; then
  command -v pod >/dev/null || { echo "CocoaPods is required for the device handwriting build" >&2; exit 1; }
  (cd "$repo_root/platforms/ios" && pod install --deployment)
  build_container=(-workspace "$repo_root/platforms/ios/MSIMEClient.xcworkspace")
fi
xcodebuild "${build_container[@]}" \
  -scheme MSIMEClientApp -sdk "$sdk" -configuration Release \
  -derivedDataPath "$repo_root/target/ios/derived-$variant" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
