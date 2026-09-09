#!/usr/bin/env bash
set -euo pipefail
readelf_tool=${1:?usage: verify-native.sh <llvm-readelf> <library-directory> <abi>}
library_dir=${2:?library directory required}
abi=${3:?ABI required}
case "$abi" in
  arm64-v8a) machine=AArch64 ;;
  x86_64) machine='Advanced Micro Devices X86-64' ;;
  *) echo "Unsupported ABI" >&2; exit 1 ;;
esac
for name in libmsime_host_api.so libmsime_android.so libc++_shared.so; do
  library="$library_dir/$name"
  header=$("$readelf_tool" -h "$library")
  [[ "$header" == *ELF64* && "$header" == *"$machine"* ]] || { echo "Wrong ELF architecture: $name" >&2; exit 1; }
  segments=$("$readelf_tool" -l --wide "$library" | awk '$1 == "LOAD" {print $NF}')
  [[ -n "$segments" ]] || exit 1
  while IFS= read -r alignment; do
    [[ "$alignment" =~ ^0x[[:xdigit:]]+$ ]] && (( alignment >= 16384 )) || { echo "LOAD alignment below 16KB: $name" >&2; exit 1; }
  done <<< "$segments"
  dependencies=$("$readelf_tool" -d "$library" | awk '/NEEDED/ {gsub(/[][]/, "", $NF); print $NF}')
  while IFS= read -r dependency; do
    case "$dependency" in
      libc.so|libm.so|libdl.so|liblog.so|libc++_shared.so|libmsime_host_api.so|'') ;;
      *) echo "Unexpected dynamic dependency: $name -> $dependency" >&2; exit 1 ;;
    esac
  done <<< "$dependencies"
  echo "$name: $abi ELF, 16KB LOAD alignment and dependency allowlist passed"
done
symbols=$("$readelf_tool" --dyn-syms --wide "$library_dir/libmsime_host_api.so")
for symbol in msime_client_create msime_client_character msime_client_update_preferences msime_client_string_free; do
  grep -Eq "GLOBAL +DEFAULT +[0-9]+ +${symbol}$" <<< "$symbols" || { echo "Missing host export: $symbol" >&2; exit 1; }
done
symbols=$("$readelf_tool" --dyn-syms --wide "$library_dir/libmsime_android.so")
for method in createRaw characterRaw updatePreferencesRaw destroyRaw; do
  grep -Eq "GLOBAL +DEFAULT +[0-9]+ +Java_app_msime_client_NativeClient_${method}$" <<< "$symbols" || { echo "Missing JNI export: $method" >&2; exit 1; }
done
