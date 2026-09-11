#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${TAG_NAME:?TAG_NAME is required}"
: "${SIGNING_ENABLED:?SIGNING_ENABLED is required}"
# push means an automatic per-merge build, anything else means somebody asked for this one. GitHub has no channel concept, so the two states it does have carry the two channels: automatic builds are prereleases, deliberate ones are ordinary releases and the newest of those takes the Latest badge. Before this the two were indistinguishable and the badge simply followed whatever merged last. Kept in step with MSIME-Windows#167.
: "${RELEASE_TRIGGER:?RELEASE_TRIGGER is required}"
# Which platforms this run publishes. A push classifies the paths that changed and a manual run is
# told; either way a platform that is not covered contributes no artifacts and no release notes,
# while a covered one still requires all of its files so a silently failed packaging step is caught
# here.
: "${RELEASE_MACOS:?RELEASE_MACOS is required}"
: "${RELEASE_IOS:?RELEASE_IOS is required}"
for flag in "$RELEASE_MACOS" "$RELEASE_IOS"; do
    case "$flag" in
        true|false) ;;
        *)
            printf '%s\n' "RELEASE_MACOS and RELEASE_IOS must be true or false." >&2
            exit 1
            ;;
    esac
done
if [[ "$RELEASE_MACOS" != true && "$RELEASE_IOS" != true ]]; then
    printf '%s\n' "A release must cover at least one platform." >&2
    exit 1
fi
: "${IOS_TESTFLIGHT_ENABLED:=false}"
if [[ ${ASSET_SUFFIX+x} != x ]]; then
    printf '%s\n' "ASSET_SUFFIX is required." >&2
    exit 1
fi

dist_dir=${DIST_DIR:-dist}
case "$IOS_TESTFLIGHT_ENABLED" in
    true|false) ;;
    *)
        printf '%s\n' "IOS_TESTFLIGHT_ENABLED must be true or false." >&2
        exit 1
        ;;
esac
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

if [[ ! "$TAG_NAME" =~ ^(macos-|ios-)?v[0-9]+\.[0-9]+\.[0-9]+(-build\.[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2})?$ ]]; then
    printf '%s\n' "Tag must use vMAJOR.MINOR.PATCH with an optional -build.X.Y.Z suffix." >&2
    exit 1
fi

# Must match how the packaging scripts name their output: the platform prefix stays on the tag and
# out of the file names, which already carry a platform segment of their own.
asset_tag=${TAG_NAME#macos-}
asset_tag=${asset_tag#ios-}
archive="$dist_dir/MetasequoiaIME-$asset_tag-macos-universal$ASSET_SUFFIX.zip"
update_archive="$dist_dir/MetasequoiaIME-$asset_tag-macos-universal$ASSET_SUFFIX-update.zip"
installer="$dist_dir/MetasequoiaIME-$asset_tag-macos-universal$ASSET_SUFFIX.pkg"
appcast="$dist_dir/appcast.xml"
if [[ "$IOS_TESTFLIGHT_ENABLED" == true ]]; then
    ios_archive="$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.xcarchive.zip"
    ios_ipa="$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.ipa"
    opposite_ios_artifacts=(
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.xcarchive.zip"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.xcarchive.zip.sha256"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.ipa"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.ipa.sha256"
    )
else
    ios_archive="$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.xcarchive.zip"
    ios_ipa="$dist_dir/MetasequoiaIME-$asset_tag-ios-unsigned.ipa"
    opposite_ios_artifacts=(
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.xcarchive.zip"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.xcarchive.zip.sha256"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.ipa"
        "$dist_dir/MetasequoiaIME-$asset_tag-ios-testflight.ipa.sha256"
    )
fi
artifacts=()
if [[ "$RELEASE_MACOS" == true ]]; then
    artifacts+=("$installer" "$installer.sha256" "$archive" "$archive.sha256"
                "$update_archive" "$update_archive.sha256")
fi
# The Sparkle appcast is signed with the project's Ed25519 update key, which is independent of Apple code signing, so publish it whenever the release job produced one.
if [[ "$RELEASE_MACOS" == true && -f "$appcast" ]]; then
    artifacts+=("$appcast")
fi
# Required rather than optional once iOS is covered: a missing archive then means the packaging
# step failed silently rather than that iOS is not being shipped by this release.
if [[ "$RELEASE_IOS" == true ]]; then
    artifacts+=("$ios_archive" "$ios_archive.sha256" "$ios_ipa" "$ios_ipa.sha256")
fi
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
    # Only what this release covers: a platform that was never packaged has no file here to hash,
    # and shasum would fail on the missing name rather than report anything about the release.
    if [[ "$RELEASE_MACOS" == true ]]; then
        verify_checksum_manifest "$(basename "$installer")" "$(basename "$installer.sha256")"
        verify_checksum_manifest "$(basename "$archive")" "$(basename "$archive.sha256")"
        verify_checksum_manifest "$(basename "$update_archive")" "$(basename "$update_archive.sha256")"
    fi
    if [[ "$RELEASE_IOS" == true ]]; then
        verify_checksum_manifest "$(basename "$ios_archive")" "$(basename "$ios_archive.sha256")"
        verify_checksum_manifest "$(basename "$ios_ipa")" "$(basename "$ios_ipa.sha256")"
    fi
)

mode_marker="<!-- metasequoia-release-mode:$release_mode -->"
opposite_marker="<!-- metasequoia-release-mode:$opposite_mode -->"
install_guidance_marker="<!-- metasequoia-install-guidance:v4 -->"
build_channel_marker="<!-- metasequoia-build-channel:v1 -->"
if [[ "$RELEASE_TRIGGER" == push ]]; then
    # Braces are required: bash takes the full-width bracket that follows as part of the name otherwise.
    release_title="${TAG_NAME}（自动构建）"
    channel=(--prerelease)
    needs_channel_note=true
else
    release_title="$TAG_NAME"
    # The Latest badge is not decoration: SUFeedURL is
    # releases/latest/download/appcast.xml, so whichever release holds the badge is the one every
    # macOS copy asks for its updates. A release that does not cover macOS carries no appcast, and
    # letting it take the badge turns that URL into a 404 -- updates stop for everyone, silently,
    # until some later macOS release takes the badge back. Passing the flag off explicitly matters:
    # omitted, the API defaults make_latest to true and the badge moves anyway.
    channel=(--prerelease=false)
    if [[ "$RELEASE_MACOS" == true ]]; then
        channel+=(--latest)
    else
        channel+=(--latest=false)
    fi
    needs_channel_note=false
fi
current_notes=$(gh release view "$TAG_NAME" --repo "$GH_REPO" --json body --jq '.body // ""')
# The iOS section is generated by this script. Drop an older generated section before writing the
# current signed/unsigned guidance so a retry cannot leave contradictory instructions behind.
base_notes=$(printf '%s\n' "$current_notes" | awk '/^<!-- metasequoia-install-guidance:v[0-9]+ -->$/{exit} /^### iOS$/{exit} {print}')
if [[ "$needs_channel_note" == true && "$current_notes" == *"$build_channel_marker"* ]]; then
    needs_channel_note=false
fi
if [[ "$current_notes" == *"$opposite_marker"* ]]; then
    printf '%s\n' "Release $TAG_NAME is already locked to $opposite_mode artifacts; refusing to switch it to $release_mode." >&2
    exit 1
fi

if [[ "$current_notes" != *"$mode_marker"* || "$current_notes" != *"$install_guidance_marker"* || "$needs_channel_note" == true ]]; then
    release_notes=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/metasequoia-release-notes.md
    {
        if [[ -n "$base_notes" ]]; then
            printf '%s\n\n' "$base_notes"
        fi
        if [[ "$needs_channel_note" == true ]]; then
            printf '%s\n' "$build_channel_marker"
            printf '%s\n\n' '> 本版本由 CI 在合并到 `main` 后自动构建发布，未经人工挑选，标记为 Pre-release。想要经过挑选的版本，请下载页面上带 Latest 徽章的那个。'
        fi
        if [[ "$current_notes" != *"$mode_marker"* ]]; then
            printf '%s\n' "$mode_marker"
            if [[ "$release_mode" == unsigned ]]; then
                printf '%s\n' '> [!WARNING] These macOS artifacts are not Developer ID signed or notarized because release signing credentials were not configured. The asset filenames are marked unsigned.'
            fi
        fi
        if [[ "$current_notes" != *"$install_guidance_marker"* ]]; then
            printf '%s\n\n' "$install_guidance_marker"
            if [[ "$RELEASE_MACOS" == true ]]; then
                printf '%s\n' '### Install on macOS'
                printf '%s\n' '- **Recommended: ZIP.** Verify its `.sha256`, extract it, then run `Install.command`. It installs for the current user, registers and enables the exact input source, and does not automatically log out or restart the Mac.'
                printf '%s\n' '- **PKG option.** The native Installer copies the same app and attempts to register and enable 水杉 for the logged-in GUI user. If no GUI user is logged in or macOS blocks the app, enable it later in System Settings > Keyboard > Text Input > Edit. The package does not force a logout or restart; macOS may still require a later logout before a newly copied input method appears.'
            fi
            if [[ "$RELEASE_IOS" == true ]]; then
                printf '\n%s\n' '### iOS'
                if [[ "$IOS_TESTFLIGHT_ENABLED" == true ]]; then
                    printf '%s\n' '- `-ios-testflight.ipa` and `-ios-testflight.xcarchive.zip` are distribution-signed with the project Team ID; the IPA is uploaded to App Store Connect for TestFlight.'
                    printf '%s\n' '- Install the processed build from TestFlight. Apple may take additional time to finish processing before it appears to testers.'
                else
                    printf '%s\n' '- Both iOS assets are **unsigned** because App Store Connect and iOS signing secrets were not configured for this run.'
                    printf '%s\n' '- `-ios-unsigned.ipa` is the one to take. Sign it with your own Apple ID using a re-signing tool such as Sideloadly or AltStore and install it; the keyboard is then enabled in Settings > General > Keyboard > Keyboards.'
                    printf '%s\n' '- `-ios-unsigned.xcarchive.zip` is for a maintainer with a Developer Program membership: open it in Xcode Organizer and distribute to TestFlight or the App Store from the exact bits this tag built, without rebuilding.'
                fi
            fi
        fi
    } > "$release_notes"
    gh release edit "$TAG_NAME" --repo "$GH_REPO" --notes-file "$release_notes"
fi

if [[ "$RELEASE_IOS" == true ]]; then
for opposite_ios_artifact in "${opposite_ios_artifacts[@]}"; do
    opposite_name=$(basename "$opposite_ios_artifact")
    if gh release view "$TAG_NAME" --repo "$GH_REPO" --json assets --jq '.assets[].name' | grep -Fxq "$opposite_name"; then
        gh release delete-asset "$TAG_NAME" --repo "$GH_REPO" "$opposite_name" --yes
    fi
done
fi
# The verified list is the uploaded list: keeping two copies is how one of them goes stale.
gh release upload "$TAG_NAME" --repo "$GH_REPO" "${artifacts[@]}" --clobber
gh release edit "$TAG_NAME" --repo "$GH_REPO" --draft=false "${channel[@]}" --title "$release_title"
