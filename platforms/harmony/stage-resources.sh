#!/usr/bin/env bash
# Stages the pinned dictionary release into the HAP, the counterpart of what build-apk.sh does for
# Android. Run it before hvigorw assembleHap; the natives come from build-native.sh.
#
# The artifacts land in resfile rather than rawfile because OpenHarmony extracts resfile to
# context.resourceDir at install time, which gives the Engine a real filesystem path. Nothing writes
# back into it: msime_client_prepare_host only verifies this directory and puts its state elsewhere,
# so the read-only extraction is enough and the 180MB first-run copy Android needs is avoided.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
resource_dir=${1:?usage: stage-resources.sh <verified-resource-directory>}
resource_dir=$(cd "$resource_dir" && pwd)
# The directory has to match the lock exactly, down to containing no extra file, because the same
# check runs again on the device inside prepare_host. Failing here is far cheaper than failing there.
artifacts=$(cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$resource_dir")
staged="$repo_root/platforms/harmony/entry/src/main/resources/resfile/engine"
rm -rf "$staged"
mkdir -p "$staged"
while IFS= read -r artifact; do cp "$resource_dir/$artifact" "$staged/"; done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$staged" >/dev/null
echo "Staged for the HAP: $staged"
