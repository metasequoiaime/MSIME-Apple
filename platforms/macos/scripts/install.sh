#!/bin/zsh
set -euo pipefail

if [[ -z ${HOME:-} || "$HOME" != /* ]]; then
    print -u2 "HOME must be an absolute current-user directory."
    exit 1
fi
home_directory=${HOME:A}
if [[ "$home_directory" == / ]]; then
    print -u2 "HOME must be an absolute current-user directory."
    exit 1
fi

project_root=${0:A:h:h:h:h}
source_bundle=${METASEQUOIA_DEVELOPMENT_BUNDLE:-"$project_root/build/MetasequoiaIME.app"}
source_bundle=${source_bundle:A}
destination_root="$home_directory/Library/Input Methods"
destination_bundle="$destination_root/MetasequoiaIME.app"
registration_command=${METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND:-"$destination_bundle/Contents/MacOS/MetasequoiaIME"}

if [[ ! -d "$source_bundle" ]]; then
    print -u2 "Build output is missing. Run platforms/macos/scripts/build.sh first."
    exit 1
fi

mkdir -p "$destination_root"
exec {install_lock_fd}>> "$destination_root/.MetasequoiaIME.install.lock"
if ! /usr/bin/lockf -s -t 0 "$install_lock_fd"; then
    print -u2 "Another MetasequoiaIME installation is already running, or the installation lock could not be acquired."
    exit 1
fi
staging_root=$(mktemp -d "$destination_root/.MetasequoiaIME.installing.XXXXXX")
backup_root=""
cleanup_setup() {
    local exit_status=$?
    trap - EXIT HUP INT TERM
    local cleanup_failed=false
    if [[ -n "$backup_root" && -e "$backup_root" ]] && ! rm -rf -- "$backup_root"; then
        cleanup_failed=true
    fi
    if [[ -e "$staging_root" ]] && ! rm -rf -- "$staging_root"; then
        cleanup_failed=true
    fi
    if [[ "$cleanup_failed" == true ]]; then
        print -u2 "Installation setup cleanup was incomplete. Temporary files may remain under: $destination_root"
        exit 1
    fi
    exit "$exit_status"
}

trap cleanup_setup EXIT
trap 'exit 1' HUP INT TERM
backup_root=$(mktemp -d "$destination_root/.MetasequoiaIME.backup.XXXXXX")
staging_bundle="$staging_root/MetasequoiaIME.app"
backup_bundle="$backup_root/MetasequoiaIME.app"
had_previous=false
moved_new=false
install_complete=false

cleanup() {
    local exit_status=$?
    trap - EXIT HUP INT TERM
    local rollback_failed=false
    if [[ "$install_complete" != true ]]; then
        if [[ "$moved_new" == true && -e "$destination_bundle" ]] &&
            ! rm -rf -- "$destination_bundle"; then
            rollback_failed=true
        fi
        if [[ "$had_previous" == true && -e "$backup_bundle" ]]; then
            if [[ -e "$destination_bundle" ]] || ! mv "$backup_bundle" "$destination_bundle"; then
                rollback_failed=true
            fi
        fi
    fi
    if [[ "$rollback_failed" == true ]]; then
        if [[ -e "$backup_bundle" ]]; then
            print -u2 "Installation rollback was incomplete. Previous installation is preserved at: $backup_bundle"
        else
            print -u2 "Installation rollback was incomplete. Recovery files are preserved at: $staging_root"
        fi
        exit 1
    fi
    if ! rm -rf -- "$staging_root" "$backup_root"; then
        print -u2 "Installation cleanup was incomplete. Recovery files may remain at: $staging_root or $backup_root"
        exit 1
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ditto "$source_bundle" "$staging_bundle"
# 构建产物是 ad-hoc 签名、不带任何 entitlement,而语音输入要 com.apple.security.device.audio-input。
# 本机有 Developer ID 就照发布流程重签一遍,让装出来的这份和用户拿到的那份行为一致。
# 权限文件里为什么没有 applesignin,见 resources/VoiceInput.entitlements 的注释 —— 简单说:
# 那是受限权限,没有 embedded.provisionprofile 就会让整个输入法在 exec 时被 AMFI 杀掉。
entitlements="${0:A:h}/../resources/VoiceInput.entitlements"
install_identity=${METASEQUOIA_SIGNING_IDENTITY:-}
if [[ -z "$install_identity" ]]; then
    install_identity=$(security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
fi
if [[ -n "$install_identity" && -f "$entitlements" ]]; then
    if codesign --force --deep --options runtime --timestamp \
        --entitlements "$entitlements" --sign "$install_identity" "$staging_bundle" 2>/dev/null; then
        print "Signed with $install_identity"
    else
        # 签名失败不该拦住安装 —— 没网时 --timestamp 就会失败,而输入法本身照样能用。
        print -u2 "Developer ID signing failed; keeping the ad-hoc signature (Apple sign-in will not work)."
    fi
fi
codesign --verify --deep --strict --verbose=2 "$staging_bundle"
process_pattern=$(printf '%s' "$destination_bundle/Contents/MacOS/MetasequoiaIME" | sed 's/[.[\\*^$()+?{|]/\\&/g')
process_pattern="^${process_pattern}( |$)"
pkill -TERM -u "$EUID" -f "$process_pattern" 2>/dev/null || true
process_stopped=false
for attempt in {1..50}; do
    process_status=0
    pgrep -u "$EUID" -f "$process_pattern" >/dev/null 2>&1 || process_status=$?
    if (( process_status == 1 )); then
        process_stopped=true
        break
    fi
    if (( process_status != 0 )); then
        print -u2 "Could not verify whether MetasequoiaIME stopped; no files were changed."
        exit 1
    fi
    if (( attempt < 50 )); then
        sleep 0.1
    fi
done
if [[ "$process_stopped" != true ]]; then
    print -u2 "MetasequoiaIME did not stop in time; no files were changed."
    exit 1
fi
if [[ -e "$destination_bundle" ]]; then
    had_previous=true
    mv "$destination_bundle" "$backup_bundle"
fi
moved_new=true
mv "$staging_bundle" "$destination_bundle"
codesign --verify --deep --strict --verbose=2 "$destination_bundle"
if ! "$registration_command" --register-input-source; then
    print -u2 "Input source registration or enable failed; restoring the previous installation."
    exit 1
fi
install_complete=true
print "Installed $destination_bundle"
print "Registered and enabled 水杉输入法 with macOS. Select it from the input menu to start typing."
