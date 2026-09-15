#!/usr/bin/env bash
# Runs the ported keyboard logic under node. HarmonyOS's own hypium tests are instrumented and need a
# device; these classes carry no ArkUI or NAPI dependency, so they can be checked here instead.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/../../.." && pwd)
tsc="$repo_root/apps/desktop/node_modules/.bin/tsc"
if [[ ! -x "$tsc" ]]; then
  echo "TypeScript compiler not found at $tsc; run pnpm install at the repository root" >&2
  exit 1
fi
"$tsc" --project "$here/tsconfig.json"
node "$repo_root/target/harmony-tests/tests/keyboard-logic.test.js"
