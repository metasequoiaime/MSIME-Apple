#!/usr/bin/env bash
# Stage locally built test dependencies only. No test execution/TSF registration.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
arch=${1:?usage: stage-runtime.sh x64|x86}
case "$arch" in
  x64) compiler=x86_64-w64-mingw32; format=pei-x86-64 ;;
  x86) compiler=i686-w64-mingw32; format=pei-i386 ;;
  *) echo "Expected x64 or x86" >&2; exit 2 ;;
esac
output="$repo_root/target/windows-full/$arch"
standard=$("$compiler-g++" -print-file-name=libstdc++-6.dll)
[[ -f "$standard" ]] || { echo "Compiler C++ runtime not found" >&2; exit 1; }
runtime_lib=$(cd "$(dirname "$standard")" && pwd)
runtime_dirs=("$runtime_lib" "$runtime_lib/../bin")
if [[ -n "${MSIME_MINGW_RUNTIME_DIR:-}" ]]; then runtime_dirs+=("$MSIME_MINGW_RUNTIME_DIR"); fi
files=(windows-registration-inbox.exe windows-focus-router.exe windows-main-frame.exe
       windows-focus-gate.exe windows-input-queue.exe windows-session-smoke.exe
       windows-reply-codec.exe windows-reply-composer.exe windows-server-smoke.exe
       windows-pipe-io.exe windows-preview-config.exe msime-client-server.exe msime_host_api.dll)
[[ -f "$output/windows-server-smoke.exe" && -f "$output/msime_host_api.dll" ]] || { echo "Run build-cross.sh first" >&2; exit 1; }
cmake -E copy_if_different "$output/tests/native-pipe/windows-pipe-io.exe" "$output/windows-pipe-io.exe"
seen='|'
index=0
while (( index < ${#files[@]} )); do
  name=${files[$index]}
  index=$((index + 1))
  case "$seen" in *"|$name|"*) continue ;; esac
  seen="$seen$name|"
  metadata=$("$compiler-objdump" -f "$output/$name")
  case "$metadata" in *"file format $format"*) ;; *) echo "Wrong architecture: $name" >&2; exit 1 ;; esac
  imports=$("$compiler-objdump" -p "$output/$name")
  while read -r dependency; do
    [[ -n "$dependency" ]] || continue
    case "$dependency" in
      libstdc++-6.dll|libgcc_s_seh-1.dll|libgcc_s_dw2-1.dll|libgcc_s_sjlj-1.dll|libwinpthread-1.dll)
        source_path=''
        for directory in "${runtime_dirs[@]}"; do
          if [[ -f "$directory/$dependency" ]]; then source_path="$directory/$dependency"; break; fi
        done
        [[ -n "$source_path" ]] || { echo "Missing matching runtime: $dependency" >&2; exit 1; }
        source_metadata=$("$compiler-objdump" -f "$source_path")
        case "$source_metadata" in *"file format $format"*) ;; *) echo "Wrong runtime architecture: $dependency" >&2; exit 1 ;; esac
        cmake -E copy_if_different "$source_path" "$output/$dependency"
        files+=("$dependency") ;;
      msime_host_api.dll) ;;
      *)
        lower=$(printf '%s' "$dependency" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
          api-ms-*.dll|ext-ms-*.dll|kernel32.dll|ntdll.dll|advapi32.dll|user32.dll|gdi32.dll|ole32.dll|shell32.dll|userenv.dll|ws2_32.dll|bcrypt.dll|bcryptprimitives.dll|ucrtbase.dll|msvcrt.dll) ;;
          *) echo "Unclassified dependency: $dependency" >&2; exit 1 ;;
        esac ;;
    esac
  done < <(printf '%s\n' "$imports" | awk '/DLL Name:/ {print $3}')
done
cmake -E copy_if_different "$repo_root/platforms/windows/tests/run-smoke.ps1" "$output/run-smoke.ps1"
echo "Staged $arch local validation directory; import graph checked, Windows execution not performed. Not a release package."
