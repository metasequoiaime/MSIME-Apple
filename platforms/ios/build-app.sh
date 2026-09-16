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

# The shipping iOS app is the shared Tauri host. The legacy SwiftUI project is
# retained for native tests and can be built explicitly while its remaining
# screens are being retired; it must not be the default product build.
if [ "${MSIME_IOS_LEGACY_APP:-0}" = 1 ]; then
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
  exit 0
fi

if [ "$variant" = device ]; then
  command -v pod >/dev/null || { echo "CocoaPods is required for the device handwriting build" >&2; exit 1; }
  (cd "$repo_root/apps/desktop/src-tauri/gen/apple" && pod install --deployment)
fi
(cd "$repo_root" && pnpm --filter @msime/desktop tauri ios build \
  --target "$tauri_target" --no-sign --ci)
