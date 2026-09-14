#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
source_dir=${1:?usage: stage-resources.sh <verified-resource-directory>}
source_dir=$(cd "$source_dir" && pwd)
destination="$repo_root/target/ios/EngineResources"
artifacts=$(cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$source_dir")
mkdir -p "$destination"
while IFS= read -r artifact; do
  cp "$source_dir/$artifact" "$destination/$artifact"
done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$destination" >/dev/null
echo "iOS resources staged from the pinned dictionary release: $destination"
