#!/usr/bin/env bash
# Cross compilation: links codec and pipe tests, but does not run Windows code.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo_root"
json_include=${1:?usage: check-cross.sh <nlohmann-json-include-root>}
[[ -f "$json_include/nlohmann/json.hpp" ]] || { echo "nlohmann JSON headers required" >&2; exit 2; }
winrt_include=${MSIME_WINRT_INCLUDE:-}
for arch in x86_64 i686; do
  output="$repo_root/target/windows-cross/$arch"
  mkdir -p "$output"
  compiler="$arch-w64-mingw32-g++"
  for source in InputQueue.cpp SessionPump.cpp SessionWorkers.cpp SessionController.cpp PreferenceMonitor.cpp WindowsServer.cpp tests/server_smoke.cpp tests/input_queue.cpp tests/session_pump.cpp tests/session_workers.cpp tests/preference_monitor.cpp; do
    "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include -Icrates/host-api/include \
      -Ivendor/MSIME-Engine/contracts -I"$json_include" -c "platforms/windows/$source" -o "$output/$(basename "$source").o"
  done
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows \
    platforms/windows/tests/registration_inbox.cpp -o "$output/registration-inbox.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/tests/focus_router.cpp -o "$output/focus-router.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/tests/main_frame.cpp -o "$output/main-frame.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include \
    -c platforms/windows/msimeui/demos/msimeui-keyboard-demo/KeyboardPanel.cpp -o "$output/keyboard-panel.o"
  if [[ -n "$winrt_include" && -f "$winrt_include/winrt/Windows.Foundation.Collections.h" ]]; then
    "$compiler" -std=c++20 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include -I"$winrt_include" \
      -c platforms/windows/msimeui/demos/msimeui-handwriting-demo/HandwritingPanel.cpp -o "$output/handwriting-panel.o"
  else
    echo "Windows C++/WinRT headers unavailable; handwriting panel cross-check skipped"
  fi
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include -I"$json_include" \
    -c platforms/windows/msimeui/demos/msimeui-emoji-panel/EmojiPanel.cpp -o "$output/emoji-panel.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/src/FocusedSession.cpp -o "$output/FocusedSession.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows \
    platforms/windows/tests/focus_gate.cpp -o "$output/focus-gate.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/src/PipeIo.cpp platforms/windows/src/PipePeer.cpp platforms/windows/src/PipeHandshake.cpp \
    platforms/windows/src/PipeListener.cpp platforms/windows/src/PipeRegistry.cpp platforms/windows/src/PipeIntake.cpp platforms/windows/src/PipeService.cpp platforms/windows/src/PipeMainTransport.cpp platforms/windows/src/ReplyCodec.cpp platforms/windows/tests/pipe_io.cpp -ladvapi32 -o "$output/pipe-io.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/src/ReplyCodec.cpp platforms/windows/tests/reply_codec.cpp -o "$output/reply-codec.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/src/ReplyComposer.cpp -o "$output/ReplyComposer.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/tests/reply_composer.cpp -o "$output/reply_composer.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/src/ServerSession.cpp -o "$output/ServerSession.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/tests/session_smoke.cpp -o "$output/session_smoke.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -c vendor/MSIME-Engine/contracts/tests/windows_ipc_contract.cpp -o "$output/windows_ipc_contract.o"
done
echo "Windows x86/x64 adapter and contract compiled, codec and pipe tests linked; no Windows runtime verified"
