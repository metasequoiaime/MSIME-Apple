#!/usr/bin/env bash
# Cross compilation: links codec and pipe tests, but does not run Windows code.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$repo_root"
json_include=${1:?usage: check-cross.sh <nlohmann-json-include-root>}
[[ -f "$json_include/nlohmann/json.hpp" ]] || { echo "nlohmann JSON headers required" >&2; exit 2; }
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
    platforms/windows/KeyboardPanel.cpp platforms/windows/msimeui/src/DeviceResources.cpp platforms/windows/msimeui/src/Fonts.cpp -municode -mwindows -luser32 -lgdi32 -lole32 -ld2d1 -ldwrite -ld3d11 -ldcomp -lwindowscodecs \
    -o "$output/keyboard-panel.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include \
    platforms/windows/HandwritingPanel.cpp platforms/windows/msimeui/src/DeviceResources.cpp platforms/windows/msimeui/src/Fonts.cpp -municode -mwindows -luser32 -lgdi32 -lole32 -ld2d1 -ldwrite -ld3d11 -ldcomp -lwindowscodecs \
    -o "$output/handwriting-panel.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Iplatforms/windows/msimeui/include -I"$json_include" \
    -c platforms/windows/EmojiPanel.cpp -o "$output/emoji-panel.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/FocusedSession.cpp -o "$output/FocusedSession.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows \
    platforms/windows/tests/focus_gate.cpp -o "$output/focus-gate.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/PipeIo.cpp platforms/windows/PipePeer.cpp platforms/windows/PipeHandshake.cpp \
    platforms/windows/PipeListener.cpp platforms/windows/PipeRegistry.cpp platforms/windows/PipeIntake.cpp platforms/windows/PipeService.cpp platforms/windows/PipeMainTransport.cpp platforms/windows/ReplyCodec.cpp platforms/windows/tests/pipe_io.cpp -ladvapi32 -o "$output/pipe-io.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Ivendor/MSIME-Engine/contracts \
    platforms/windows/ReplyCodec.cpp platforms/windows/tests/reply_codec.cpp -o "$output/reply-codec.exe"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/ReplyComposer.cpp -o "$output/ReplyComposer.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/tests/reply_composer.cpp -o "$output/reply_composer.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/ServerSession.cpp -o "$output/ServerSession.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -Iplatforms/windows -Icrates/host-api/include \
    -Ivendor/MSIME-Engine/contracts -I"$json_include" -c platforms/windows/tests/session_smoke.cpp -o "$output/session_smoke.o"
  "$compiler" -std=c++17 -Wall -Wextra -Werror -c vendor/MSIME-Engine/contracts/tests/windows_ipc_contract.cpp -o "$output/windows_ipc_contract.o"
done
echo "Windows x86/x64 adapter and contract compiled, codec and pipe tests linked; no Windows runtime verified"
