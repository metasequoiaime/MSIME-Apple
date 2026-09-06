#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${SIGNING_ENABLED:?SIGNING_ENABLED is required}"
if [[ ${ASSET_SUFFIX+x} != x ]]; then
    printf '%s\n' "ASSET_SUFFIX is required." >&2
    exit 1
fi

dist_dir=${DIST_DIR:-dist}
case "$SIGNING_ENABLED:$ASSET_SUFFIX" in
    true:)
        release_mode=signed
        opposite_mode=unsigned
        ;;
    false:-unsigned)
        release_mode=unsigned
        opposite_mode=signed
        ;;
    *)
        printf '%s\n' "Release signing mode and asset suffix do not agree." >&2
        exit 1
        ;;
esac

if [[ ! "$TAG_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "Tag must use the vMAJOR.MINOR.PATCH format." >&2
    exit 1
fi

archive="$dist_dir/MetasequoiaIME-$TAG_NAME-macos-universal$ASSET_SUFFIX.zip"
update_archive="$dist_dir/MetasequoiaIME-$TAG_NAME-macos-universal$ASSET_SUFFIX-update.zip"
installer="$dist_dir/MetasequoiaIME-$TAG_NAME-macos-universal$ASSET_SUFFIX.pkg"
appcast="$dist_dir/appcast.xml"
# The iOS archive carries no Apple signature in any release mode, so its name does not take
# ASSET_SUFFIX — there is no signed counterpart for it to be distinguished from.
ios_archive="$dist_dir/MetasequoiaIME-$TAG_NAME-ios-unsigned.xcarchive.zip"
ios_ipa="$dist_dir/MetasequoiaIME-$TAG_NAME-ios-unsigned.ipa"
artifacts=("$installer" "$installer.sha256" "$archive" "$archive.sha256" "$update_archive" "$update_archive.sha256")
# The Sparkle appcast is signed with the project's Ed25519 update key, which is independent of Apple code signing, so publish it whenever the release job produced one.
if [[ -f "$appcast" ]]; then
    artifacts+=("$appcast")
fi
# Required rather than optional: the iOS build is part of every release run, so a missing archive
# means the step failed silently rather than that iOS is not being shipped.
artifacts+=("$ios_archive" "$ios_archive.sha256" "$ios_ipa" "$ios_ipa.sha256")
for artifact in "${artifacts[@]}"; do
    if [[ ! -f "$artifact" ]]; then
        printf 'Release artifact is missing: %s\n' "$artifact" >&2
        exit 1
    fi
done
(
    cd "$dist_dir"
    verify_checksum_manifest() {
        local artifact_name=$1
        local manifest_name=$2
        local expected_line
        local manifest_line
        expected_line=$(shasum -a 256 "$artifact_name")
        manifest_line=$(command cat "$manifest_name")
        if [[ "$manifest_line" != "$expected_line" ]]; then
            printf 'Release checksum verification FAILED for %s.\n' "$artifact_name" >&2
            return 1
        fi
    }
    verify_checksum_manifest "$(basename "$installer")" "$(basename "$installer.sha256")"
    verify_checksum_manifest "$(basename "$archive")" "$(basename "$archive.sha256")"
    verify_checksum_manifest "$(basename "$update_archive")" "$(basename "$update_archive.sha256")"
    verify_checksum_manifest "$(basename "$ios_archive")" "$(basename "$ios_archive.sha256")"
    verify_checksum_manifest "$(basename "$ios_ipa")" "$(basename "$ios_ipa.sha256")"
)

mode_marker="<!-- metasequoia-release-mode:$release_mode -->"
opposite_marker="<!-- metasequoia-release-mode:$opposite_mode -->"
install_guidance_marker="<!-- metasequoia-install-guidance:v3 -->"
current_notes=$(gh release view "$TAG_NAME" --repo "$GH_REPO" --json body --jq '.body // ""')
if [[ "$current_notes" == *"$opposite_marker"* ]]; then
    printf '%s\n' "Release $TAG_NAME is already locked to $opposite_mode artifacts; refusing to switch it to $release_mode." >&2
    exit 1
fi

if [[ "$current_notes" != *"$mode_marker"* || "$current_notes" != *"$install_guidance_marker"* ]]; then
    release_notes=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/metasequoia-release-notes.md
    {
        if [[ -n "$current_notes" ]]; then
            printf '%s\n\n' "$current_notes"
        fi
        if [[ "$current_notes" != *"$mode_marker"* ]]; then
            printf '%s\n' "$mode_marker"
            if [[ "$release_mode" == unsigned ]]; then
                printf '%s\n' '> [!WARNING] These macOS artifacts are not Developer ID signed or notarized because release signing credentials were not configured. The asset filenames are marked unsigned.'
            fi
        fi
        if [[ "$current_notes" != *"$install_guidance_marker"* ]]; then
            printf '%s\n\n' "$install_guidance_marker"
            printf '%s\n' '### Install on macOS'
            printf '%s\n' '- **Recommended: ZIP.** Verify its `.sha256`, extract it, then run `Install.command`. It installs for the current user, registers and enables the exact input source, and does not automatically log out or restart the Mac.'
            printf '%s\n' '- **PKG option.** The native Installer copies the same app and attempts to register and enable 水杉 for the logged-in GUI user. If no GUI user is logged in or macOS blocks the app, enable it later in System Settings > Keyboard > Text Input > Edit. The package does not force a logout or restart; macOS may still require a later logout before a newly copied input method appears.'
            printf '\n%s\n' '### iOS'
            printf '%s\n' '- Both iOS assets are **unsigned**: this project has no Apple signing identity, so neither will run on a device until it is signed.'
            printf '%s\n' '- `-ios-unsigned.ipa` is the one to take. Sign it with your own Apple ID using a re-signing tool such as Sideloadly or AltStore and install it; the keyboard is then enabled in Settings > General > Keyboard > Keyboards. A free Apple ID signature expires after 7 days and a paid Developer Program one after a year, at which point it has to be re-signed.'
            printf '%s\n' '- `-ios-unsigned.xcarchive.zip` is for a maintainer with a Developer Program membership: open it in Xcode Organizer and distribute to TestFlight or the App Store from the exact bits this tag built, without rebuilding.'
        fi
    } > "$release_notes"
    gh release edit "$TAG_NAME" --repo "$GH_REPO" --notes-file "$release_notes"
fi

upload_args=("$installer" "$installer.sha256" "$archive" "$archive.sha256" "$update_archive" "$update_archive.sha256" "$ios_archive" "$ios_archive.sha256" "$ios_ipa" "$ios_ipa.sha256")
if [[ -f "$appcast" ]]; then
    upload_args+=("$appcast")
fi
gh release upload "$TAG_NAME" --repo "$GH_REPO" "${upload_args[@]}" --clobber
gh release edit "$TAG_NAME" --repo "$GH_REPO" --draft=false
