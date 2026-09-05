#!/bin/zsh
set -euo pipefail

project_root=${METASEQUOIA_PROJECT_ROOT:-${0:A:h:h:h:h}}
project_root=${project_root:A}
# Derived from the project root like every other input. It used to be derived from $0, which is the
# script's own location: the release workflow stages this script into $RUNNER_TEMP and runs it from
# there, so the path resolved outside the checkout entirely. Only the signed branch reads it, which
# is why unsigned releases never noticed.
voice_entitlements=${METASEQUOIA_VOICE_ENTITLEMENTS:-$project_root/platforms/macos/resources/VoiceInput.entitlements}
voice_entitlements=${voice_entitlements:A}
install_script=${METASEQUOIA_RELEASE_INSTALL_SCRIPT:-$project_root/platforms/macos/scripts/install-release.sh}
install_script=${install_script:A}
uninstall_script=${METASEQUOIA_RELEASE_UNINSTALL_SCRIPT:-$project_root/platforms/macos/scripts/uninstall.sh}
uninstall_script=${uninstall_script:A}
settings_script=${METASEQUOIA_RELEASE_SETTINGS_SCRIPT:-$project_root/platforms/macos/scripts/open-settings.sh}
settings_script=${settings_script:A}
settings_capability_marker="$project_root/platforms/macos/scripts/open-settings.sh"
include_settings_launcher=false
installer_distribution=${METASEQUOIA_INSTALLER_DISTRIBUTION:-$project_root/platforms/macos/resources/InstallerDistribution.xml.in}
installer_distribution=${installer_distribution:A}
# The one script in the .pkg that macOS runs on its own at install time, so it takes the same
# trusted-checkout override as the other installer scripts rather than coming from the release tag.
postinstall_script=${METASEQUOIA_RELEASE_POSTINSTALL_SCRIPT:-$project_root/platforms/macos/scripts/pkg-postinstall.sh}
postinstall_script=${postinstall_script:A}
tag_name=${1:-}
source_bundle=${2:-$project_root/build/MetasequoiaIME.app}
output_dir=${3:-$project_root/dist}

if [[ ! "$tag_name" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "Tag must use the vMAJOR.MINOR.PATCH format."
    exit 1
fi

source_bundle=${source_bundle:A}
output_dir=${output_dir:A}
version=${tag_name#v}
require_release_signing=${METASEQUOIA_REQUIRE_RELEASE_SIGNING:-false}
application_identity=${METASEQUOIA_DEVELOPER_ID_APPLICATION:-}
installer_identity=${METASEQUOIA_DEVELOPER_ID_INSTALLER:-}
notary_profile=${METASEQUOIA_NOTARY_PROFILE:-}
asset_suffix=${METASEQUOIA_RELEASE_ASSET_SUFFIX:-}

if [[ "$require_release_signing" != true && "$require_release_signing" != false ]]; then
    print -u2 "METASEQUOIA_REQUIRE_RELEASE_SIGNING must be true or false."
    exit 1
fi

if [[ "$require_release_signing" == true ]]; then
    if [[ -z "$application_identity" || -z "$installer_identity" || -z "$notary_profile" ]]; then
        print -u2 "Commercial release signing requires METASEQUOIA_DEVELOPER_ID_APPLICATION, METASEQUOIA_DEVELOPER_ID_INSTALLER, and METASEQUOIA_NOTARY_PROFILE."
        exit 1
    fi
    if [[ -n "$asset_suffix" ]]; then
        print -u2 "Signed release artifacts must not use an asset suffix."
        exit 1
    fi
else
    if [[ "$asset_suffix" != -unsigned ]]; then
        print -u2 "Unsigned release artifacts require METASEQUOIA_RELEASE_ASSET_SUFFIX=-unsigned."
        exit 1
    fi
    if [[ -n "$application_identity" || -n "$installer_identity" || -n "$notary_profile" ]]; then
        print -u2 "Unsigned release packaging does not accept signing identities or a notary profile."
        exit 1
    fi
fi

if [[ ! -d "$source_bundle" ]]; then
    print -u2 "Input method bundle not found at $source_bundle"
    exit 1
fi
if [[ ! -f "$install_script" ]]; then
    print -u2 "Release install script not found at $install_script"
    exit 1
fi
if [[ ! -f "$uninstall_script" ]]; then
    print -u2 "Release uninstall script not found at $uninstall_script"
    exit 1
fi
if [[ -f "$settings_capability_marker" ]]; then
    include_settings_launcher=true
    if [[ ! -f "$settings_script" ]]; then
        print -u2 "Settings launcher script not found at $settings_script"
        exit 1
    fi
fi
if [[ ! -f "$installer_distribution" ]]; then
    print -u2 "Installer distribution template not found at $installer_distribution"
    exit 1
fi
if [[ ! -f "$voice_entitlements" ]]; then
    print -u2 "Voice input entitlements not found at $voice_entitlements"
    exit 1
fi
if [[ ! -f "$postinstall_script" ]]; then
    print -u2 "Installer postinstall script not found at $postinstall_script"
    exit 1
fi
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_bundle/Contents/Info.plist")
if [[ "$bundle_version" != "$version" ]]; then
    print -u2 "Bundle version $bundle_version does not match tag $tag_name."
    exit 1
fi

if [[ "$require_release_signing" == true ]]; then
    codesign --verify --deep --strict --verbose=2 "$source_bundle"
else
    printf '%s\n' 'Unsigned release: skipping source bundle Developer ID signature verification.'
fi
mkdir -p "$output_dir"
staging_root=$(mktemp -d "$output_dir/.package.XXXXXX")
package_root="$staging_root/MetasequoiaIME-$tag_name"
archive_name="MetasequoiaIME-$tag_name-macos-universal$asset_suffix.zip"
update_archive_name="MetasequoiaIME-$tag_name-macos-universal$asset_suffix-update.zip"
installer_name="MetasequoiaIME-$tag_name-macos-universal$asset_suffix.pkg"
archive_path="$staging_root/$archive_name"
checksum_path="$archive_path.sha256"
update_archive_path="$staging_root/$update_archive_name"
update_checksum_path="$update_archive_path.sha256"
installer_path="$staging_root/$installer_name"
installer_checksum_path="$installer_path.sha256"
final_archive_path="$output_dir/$archive_name"
final_checksum_path="$final_archive_path.sha256"
final_update_archive_path="$output_dir/$update_archive_name"
final_update_checksum_path="$final_update_archive_path.sha256"
final_installer_path="$output_dir/$installer_name"
final_installer_checksum_path="$final_installer_path.sha256"
component_package="$staging_root/MetasequoiaIME.pkg"
distribution_file="$staging_root/Distribution.xml"
installer_resources="$staging_root/InstallerResources"
installer_readme="$installer_resources/InstallerReadMe.txt"
pkg_scripts="$staging_root/pkg-scripts"
backup_root="$staging_root/PreviousAssets"
publish_started=false
publish_complete=false
staged_assets=("$archive_path" "$checksum_path" "$update_archive_path" "$update_checksum_path" "$installer_path" "$installer_checksum_path")
final_assets=("$final_archive_path" "$final_checksum_path" "$final_update_archive_path" "$final_update_checksum_path" "$final_installer_path" "$final_installer_checksum_path")
backup_assets=("$backup_root/$archive_name" "$backup_root/$archive_name.sha256" "$backup_root/$update_archive_name" "$backup_root/$update_archive_name.sha256" "$backup_root/$installer_name" "$backup_root/$installer_name.sha256")

cleanup() {
    local exit_status=$?
    trap - EXIT HUP INT TERM
    local rollback_failed=false
    local index
    if [[ "$publish_started" == true && "$publish_complete" != true ]]; then
        for index in 1 2 3 4 5 6; do
            if [[ ! -e "${staged_assets[$index]}" && -e "${final_assets[$index]}" ]] &&
                ! rm -f -- "${final_assets[$index]}"; then
                rollback_failed=true
            fi
            if [[ -e "${backup_assets[$index]}" ]] &&
                ! mv -f -- "${backup_assets[$index]}" "${final_assets[$index]}"; then
                rollback_failed=true
            fi
        done
    fi
    if [[ "$rollback_failed" == true ]]; then
        print -u2 "Release packaging rollback was incomplete. PreviousAssets are preserved at: $backup_root"
        exit 1
    fi
    if ! rm -rf -- "$staging_root"; then
        print -u2 "Release packaging cleanup was incomplete: $staging_root"
        exit 1
    fi
    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$package_root"
packaged_bundle="$package_root/MetasequoiaIME.app"
bundled_uninstaller="$packaged_bundle/Contents/Resources/Uninstall.command"
ditto "$source_bundle" "$packaged_bundle"
mkdir -p "$packaged_bundle/Contents/Resources"
ditto "$uninstall_script" "$bundled_uninstaller"
chmod +x "$bundled_uninstaller"
# Automatic update checks stay at the Info.plist default for every release mode. Unsigned releases
# do publish appcast.xml — generate-sparkle-appcast.sh accepts the -unsigned-update.zip asset and
# the feed is signed with the project's Ed25519 update key, which is independent of Apple signing —
# so disabling checks here left every installed copy blind to updates that were already published.
if [[ -n "$application_identity" ]]; then
    codesign --force --deep --options runtime --timestamp --entitlements "$voice_entitlements" --sign "$application_identity" "$packaged_bundle"
else
    codesign --force --deep --sign - "$packaged_bundle"
fi
codesign --verify --deep --strict --verbose=2 "$packaged_bundle"
ditto "$install_script" "$package_root/Install.command"
if [[ "$include_settings_launcher" == true ]]; then
    ditto "$settings_script" "$package_root/Open Settings.command"
    chmod +x "$package_root/Open Settings.command"
fi
ditto "$uninstall_script" "$package_root/Uninstall.command"
ditto "$project_root/LICENSE" "$package_root/LICENSE"
ditto "$project_root/THIRD_PARTY_NOTICES.txt" "$package_root/THIRD_PARTY_NOTICES.txt"
if [[ "$asset_suffix" == -unsigned ]]; then
    printf '%s\n' \
        'UNSIGNED TEST BUILD' \
        '' \
        'This build is not Developer ID signed or notarized. macOS may block it until you explicitly allow it in System Settings > Privacy & Security.' \
        'Install.command requires typed confirmation before installing this build.' \
        > "$package_root/UNSIGNED_BUILD.txt"
fi
chmod +x "$package_root/Install.command"
chmod +x "$package_root/Uninstall.command"
mkdir -p "$pkg_scripts"
ditto "$postinstall_script" "$pkg_scripts/postinstall"
chmod +x "$pkg_scripts/postinstall"
if [[ -n "$notary_profile" ]]; then
    notary_input="$staging_root/MetasequoiaIME-notary.zip"
    ditto -c -k --keepParent "$packaged_bundle" "$notary_input"
    xcrun notarytool submit "$notary_input" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$packaged_bundle"
    xcrun stapler validate "$packaged_bundle"
fi
ditto -c -k --keepParent "$packaged_bundle" "$update_archive_path"
(cd "$staging_root" && shasum -a 256 "$update_archive_name") > "$update_checksum_path"
ditto -c -k --keepParent "$package_root" "$archive_path"
(cd "$staging_root" && shasum -a 256 "$archive_name") > "$checksum_path"
pkgbuild --component "$packaged_bundle" --identifier com.houko.inputmethod.MetasequoiaIME.pkg --version "$version" --scripts "$pkg_scripts" --install-location "Library/Input Methods" "$component_package"
sed "s/@VERSION@/$version/g" "$installer_distribution" > "$distribution_file"
mkdir -p "$installer_resources"
ditto "$project_root/LICENSE" "$installer_resources/LICENSE"
ditto "$project_root/THIRD_PARTY_NOTICES.txt" "$installer_resources/THIRD_PARTY_NOTICES.txt"
if [[ "$asset_suffix" == -unsigned ]]; then
    printf '%s\n' \
        'UNSIGNED TEST BUILD' \
        '' \
        'This package is not Developer ID signed or notarized. Before installing, verify the downloaded .pkg SHA-256 checksum against the companion .sha256 file and install only if you trust the source.' \
        '' \
        'macOS may block this installer until you explicitly allow it in System Settings > Privacy & Security.' \
        > "$installer_readme"
else
    printf '%s\n' \
        'SIGNED RELEASE' \
        '' \
        'This package is Developer ID signed and notarized for distribution outside the Mac App Store.' \
        > "$installer_readme"
fi
printf '%s\n' \
    '' \
    'Installation scope: current user (~/Library/Input Methods).' \
    'The native Installer may request administrator authorization.' \
    'After installation, the package attempts to register and enable 水杉 for the logged-in GUI user.' \
    'The installer will not log out or restart the Mac automatically.' \
    'macOS may list a newly copied input method only after you log out and back in at a convenient time.' \
    '' \
    'Uninstall from Terminal with:' \
    '"$HOME/Library/Input Methods/MetasequoiaIME.app/Contents/Resources/Uninstall.command"' \
    '' \
    'Third-party notices' \
    '-------------------' \
    >> "$installer_readme"
command cat "$project_root/THIRD_PARTY_NOTICES.txt" >> "$installer_readme"
productbuild --distribution "$distribution_file" --package-path "$staging_root" --resources "$installer_resources" "$installer_path"
if [[ -n "$installer_identity" ]]; then
    signed_installer="$staging_root/MetasequoiaIME-signed.pkg"
    productsign --sign "$installer_identity" "$installer_path" "$signed_installer"
    mv "$signed_installer" "$installer_path"
fi
if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$installer_path" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$installer_path"
    xcrun stapler validate "$installer_path"
fi
(cd "$staging_root" && shasum -a 256 "$installer_name") > "$installer_checksum_path"
mkdir -p "$backup_root"
publish_started=true
for index in 1 2 3 4 5 6; do
    if [[ -e "${final_assets[$index]}" ]]; then
        mv "${final_assets[$index]}" "${backup_assets[$index]}"
    fi
done
for index in 1 2 3 4 5 6; do
    mv -f "${staged_assets[$index]}" "${final_assets[$index]}"
done
publish_complete=true
print "$final_archive_path"
print "$final_checksum_path"
print "$final_update_archive_path"
print "$final_update_checksum_path"
print "$final_installer_path"
print "$final_installer_checksum_path"
