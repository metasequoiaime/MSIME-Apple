#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
source_dir=${1:?usage: stage-resources.sh <verified-resource-directory> [settled-model-directory]}
source_dir=$(cd "$source_dir" && pwd)
destination="$repo_root/target/macos/EngineResources"

# Use the shared verifier as the source of truth. The staged directory is ignored
# build output and is rebuilt as one unit, so a failed copy cannot look complete.
artifacts=$(cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$source_dir")
rm -rf "$destination"
mkdir -p "$destination"
while IFS= read -r artifact; do
  cp "$source_dir/$artifact" "$destination/$artifact"
done <<< "$artifacts"
cargo run --quiet -p msime-client-core --example verify_resources --locked -- "$destination" >/dev/null

# The settled-rerank model, staged as a sibling of the bundle rather than a member of it.
#
# A member would fail the verifier immediately above, which requires this directory to hold exactly
# the artifacts the dictionary lock pins — the check whose job is to prove a shipped dictionary is
# intact. `prepare_host_configuration` looks for the sibling and names it in the runtime options.
#
# Optional: 25 MB buying a desktop-only improvement, fetched by scripts/fetch_settled_model.py.
# Without it the host behaves exactly as it does today.
settled_source=${2:-$repo_root/target/settled-model}
settled_destination="$repo_root/target/macos/settled-model"
rm -rf "$settled_destination"
if [ -f "$settled_source/sentence-model-desktop.safetensors" ]; then
  mkdir -p "$settled_destination"
  cp "$settled_source/sentence-model-desktop.safetensors" "$settled_destination/"
  echo "settled model staged: $settled_destination"
else
  echo "no settled model at $settled_source; the desktop rerank pass stays off"
fi
echo "macOS resources staged from the pinned dictionary release: $destination"
