#!/usr/bin/env bash
# Manual portable test. Does not exercise Windows authentication or audio.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
output="$repo_root/target/voice-wire-interop"
mkdir -p "$output"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$repo_root/vendor/MSIME-Engine/contracts" \
  "$repo_root/platforms/windows/tests/voice_wire_peer.cpp" -o "$output/peer"
rustc --edition=2021 --test -D warnings \
  "$repo_root/platforms/windows/tests/voice_wire_interop.rs" -o "$output/tests"
MSIME_VOICE_WIRE_PEER="$output/peer" "$output/tests"
