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
# Helpcode tables are an Engine asset, not part of the dictionary release, so they come from the prepared Engine tree at the paths its asset contract names. Without them the Engine has nothing to match: Shift letters are taken as helpcode and narrow nothing.
engine="$repo_root/vendor/MSIME-Engine"
[ -f "$engine/contracts/assets/assets.json" ] || { echo "Engine is not prepared: run scripts/fetch_engine.py" >&2; exit 1; }
rm -rf "$destination/helpcodes"
mkdir -p "$destination/helpcodes"
python3 - "$engine" "$destination" <<'PY'
import json, shutil, sys
from pathlib import Path
engine, destination = Path(sys.argv[1]), Path(sys.argv[2])
contract = json.loads((engine / "contracts/assets/assets.json").read_text(encoding="utf-8"))
for asset in contract["assets"]:
    if "schema" in asset:
        shutil.copyfile(engine / asset["source"], destination / asset["path"])
PY
cp "$engine/helpcode/NOTICE.md" "$destination/helpcodes/NOTICE.md"
cp "$repo_root/resources/helpcodes/NOTICE.md" "$destination/helpcodes/NOTICE-jiajia.md"
echo "iOS resources staged from the pinned dictionary release: $destination"
