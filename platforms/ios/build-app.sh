#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
resource_dir=${1:?usage: build-app.sh <verified-resource-directory> [device|simulator]}
variant=${2:-simulator}
case "$variant" in
  device) sdk=iphoneos ;;
  simulator) sdk=iphonesimulator ;;
  *) echo "Unsupported iOS variant: $variant" >&2; exit 2 ;;
esac

bash "$repo_root/platforms/ios/stage-resources.sh" "$resource_dir"
bash "$repo_root/platforms/ios/build-native.sh" "$variant"
(cd "$repo_root/platforms/ios" && xcodegen generate -s project.yml -p .)
xcodebuild -project "$repo_root/platforms/ios/MSIMEClient.xcodeproj" \
  -scheme MSIMEClientApp -sdk "$sdk" -configuration Release \
  -derivedDataPath "$repo_root/target/ios/derived-$variant" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
