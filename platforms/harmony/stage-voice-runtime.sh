#!/usr/bin/env bash
# Stages the pinned sherpa-onnx HAR that on-device dictation (the `local` voice provider) runs on. Run it before ohpm install / hvigorw assembleHap, alongside stage-resources.sh and build-native.sh.
#
# The package is an upstream prebuilt pinned by SHA-256 in resources/voice-runtime.lock.json and verified by fetch_voice_runtime.py before it is copied. It lands in entry/libs, which is ignored like the natives beside it, and entry/oh-package.json5 depends on it there by a fixed name so the lock pin, not the manifest, decides the version.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo_root"
runtime_dir=$(python3 scripts/fetch_voice_runtime.py --platform harmony)
har_name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["platforms"]["harmony"]["name"])' resources/voice-runtime.lock.json)
staged="$repo_root/platforms/harmony/entry/libs/sherpa_onnx.har"
mkdir -p "$(dirname "$staged")"
cp "$runtime_dir/$har_name" "$staged"
echo "Staged for the HAP: $staged"
