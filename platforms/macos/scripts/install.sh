#!/usr/bin/env bash
# Install the built input method into ~/Library/Input Methods and register it as an input source.
#
# The bundle CMake produces is ad-hoc signed and carries no entitlements. macOS will not register an input
# source from it: --register-input-source returns 1 and the source never reaches TISCreateInputSourceList,
# so the input method cannot be selected at all. It has to be signed first, and voice input additionally
# needs com.apple.security.device.audio-input, which only arrives with an entitlements file.
#
# The first --register-input-source after replacing a bundle can return 0 on a stale LaunchServices entry
# from the previous one. That is why this script checks the registry afterwards rather than trusting the
# exit code, and why a failure here is a failure of the install rather than a warning.
#
# Usage: platforms/macos/scripts/install.sh [path/to/bundle.app]
#   MSIME_SIGNING_IDENTITY       signing identity; defaults to the first Developer ID Application found
#   MSIME_INPUT_METHODS_DIR      destination; defaults to ~/Library/Input Methods
set -euo pipefail

name="水杉输入法（预览）.app"
executable="水杉输入法（预览）"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source_bundle="${1:-$root/target/macos/$name}"
destination_root="${MSIME_INPUT_METHODS_DIR:-$HOME/Library/Input Methods}"
entitlements="$root/platforms/macos/resources/VoiceInput.entitlements"

if [ ! -d "$source_bundle" ]; then
  echo "no bundle at $source_bundle; build MSIMEClientInputMethod first (see platforms/macos/README.md)" >&2
  exit 1
fi
[ -d "$destination_root" ] || mkdir -p "$destination_root"
destination="$destination_root/$name"

# Never replace a bundle out from under a running process: macOS lets the files go while the process keeps
# running against them, which leaves an input method serving a version that no longer exists on disk.
if pgrep -f "$destination/Contents/MacOS/$executable" >/dev/null 2>&1; then
  echo "stopping the running input method"
  pkill -f "$destination/Contents/MacOS/$executable" || true
  for _ in $(seq 1 50); do
    pgrep -f "$destination/Contents/MacOS/$executable" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "$destination/Contents/MacOS/$executable" >/dev/null 2>&1; then
    echo "it did not stop; nothing was changed" >&2
    exit 1
  fi
fi

staging="$(mktemp -d "$destination_root/.msime-staging.XXXXXX")"
backup=""
restore() {
  status=$?
  if [ "$status" -ne 0 ]; then
    if [ -n "$backup" ] && [ -d "$backup/$name" ]; then
      rm -rf "$destination"
      mv "$backup/$name" "$destination" && echo "restored the previous installation" >&2
    fi
  fi
  [ -n "$backup" ] && rm -rf "$backup"
  rm -rf "$staging"
  exit "$status"
}
trap restore EXIT

ditto "$source_bundle" "$staging/$name"

# Sign the staged copy, not the destination: a half-signed bundle must never be the installed one.
identity="${MSIME_SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$identity" ]; then
  echo "no Developer ID Application identity found; set MSIME_SIGNING_IDENTITY" >&2
  echo "an ad-hoc signed bundle will not register as an input source" >&2
  exit 1
fi
# --deep, because the nested code arrives signed by whoever published it. Sparkle ships signed by the
# Sparkle project, and under the hardened runtime a process cannot load a library whose Team ID differs
# from its own:
#
#   code signature in '.../Sparkle.framework/Versions/B/Sparkle' not valid for use in process:
#   mapping process and mapped file (non-platform) have different Team IDs
#
# which kills the input method on launch, so it never registers. Apple discourages --deep for distribution
# signing; this is a local install of a bundle whose nested code is a pinned framework and one dylib we
# built ourselves, and re-signing all of it with one identity is exactly what is needed.
#
# --timestamp needs the network. Losing it is not a reason to refuse to install; the signature is still
# valid locally, which is all a local install needs.
codesign --force --deep --options runtime --timestamp --entitlements "$entitlements" --sign "$identity" \
  "$staging/$name" 2>/dev/null ||
  codesign --force --deep --options runtime --entitlements "$entitlements" --sign "$identity" "$staging/$name"
codesign --verify --strict "$staging/$name"
echo "signed with $identity"

if [ -d "$destination" ]; then
  backup="$(mktemp -d "$destination_root/.msime-backup.XXXXXX")"
  mv "$destination" "$backup/$name"
fi
mv "$staging/$name" "$destination"

"$destination/Contents/MacOS/$executable" --register-input-source
# The exit code alone is not evidence: a stale LaunchServices entry from the bundle that was just replaced
# makes the first call succeed whether or not this one registered. Ask the registry.
"$root/platforms/macos/scripts/check_input_source.swift" "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$destination/Contents/Info.plist")"
echo "installed $destination"
echo "select 水杉输入法（预览） from the input menu to start typing"
