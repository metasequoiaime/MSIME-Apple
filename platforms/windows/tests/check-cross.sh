#!/usr/bin/env bash
# Cross compilation: links the pure codec test, but does not run Windows code.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo_root"
json_include=${1:?usage: check-cross.sh <nlohmann-json-include-root>}
[[ -f "$json_include/nlohmann/json.hpp" ]] || { echo "nlohmann JSON headers required" >&2; exit 2; }
for arch in x86_64 i686; do
  output="$repo_root/target/windows-cross/$arch"
  mkdir -p "$output"
  compiler="$arch-w64-mingw32-g++"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/ReplyCodec.cpp platforms/windows/tests/reply_codec.cpp -o "$output/reply-codec.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/ServerSession.cpp -o "$output/ServerSession.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/tests/session_smoke.cpp -o "$output/session_smoke.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -c vendor/MSIME-Engine/contracts/tests/windows_ipc_contract.cpp -o "$output/windows_ipc_contract.o"
done
echo "Windows x86/x64 adapter and contract compiled, codec test linked; no Windows runtime verified"
