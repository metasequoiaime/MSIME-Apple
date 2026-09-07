#!/usr/bin/env bash
set -euo pipefail

# Build a distribution-signed iOS archive with checked-in project settings and downloaded profiles,
# preserve the signed artifacts for the GitHub Release, then upload the IPA to App Store Connect.

project_root=${METASEQUOIA_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
project_root=$(cd "$project_root" && pwd)
tag_name=${1:-}

: "${METASEQUOIA_IOS_TEAM_ID:?METASEQUOIA_IOS_TEAM_ID is required}"
: "${METASEQUOIA_IOS_AUTH_KEY_ID:?METASEQUOIA_IOS_AUTH_KEY_ID is required}"
: "${METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID:?METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID is required}"
: "${METASEQUOIA_IOS_AUTH_KEY_PATH:?METASEQUOIA_IOS_AUTH_KEY_PATH is required}"
: "${METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH:?METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH is required}"
: "${METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH:?METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH is required}"

if [[ ! "$tag_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' 'Tag must use the vMAJOR.MINOR.PATCH format.' >&2
    exit 1
fi
if [[ ! -s "$METASEQUOIA_IOS_AUTH_KEY_PATH" ]]; then
    printf 'App Store Connect API key not found at %s\n' "$METASEQUOIA_IOS_AUTH_KEY_PATH" >&2
    exit 1
fi
for profile in \
    "$METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH" \
    "$METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH"; do
    if [[ ! -s "$profile" ]]; then
        printf 'Provisioning profile not found at %s\n' "$profile" >&2
        exit 1
    fi
done

for tool in xcodegen xcodebuild xcrun; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done

spec="$project_root/platforms/ios/project.yml"
dictionary="$project_root/platforms/ios/KeyboardExtension/Resources/msime.db"
if [[ ! -f "$spec" ]]; then
    printf 'iOS project spec not found at %s\n' "$spec" >&2
    exit 1
fi
if [[ ! -s "$dictionary" ]]; then
    printf 'iOS dictionary not found at %s. Run platforms/ios/scripts/prepare_dictionary.py first.\n' "$dictionary" >&2
    exit 1
fi

version=${tag_name#v}
build_root="$project_root/build/ios-testflight"
archive_path="$build_root/MetasequoiaIME.xcarchive"
export_path="$build_root/export"
rm -rf -- "$build_root"
mkdir -p "$build_root" "$export_path"

xcodegen generate --spec "$spec" --project "$build_root" --project-root "$project_root"

# Older release tags can carry a stale host profile specifier even when the workflow supplies a
# current profile. Rewrite only the generated project, leaving the historical source tag intact,
# so a retry of an old release uses the profile that was actually injected by CI.
profile_name() {
    security cms -D -i "$1" | plutil -extract Name raw -o - -
}
configured_profile_name() {
    local bundle_identifier=$1
    awk -v bundle_identifier="$bundle_identifier" '
        $0 ~ "PRODUCT_BUNDLE_IDENTIFIER: " bundle_identifier "$" { in_target = 1; next }
        in_target && /PROVISIONING_PROFILE_SPECIFIER:/ {
            sub(/^[^:]+: /, "")
            print
            exit
        }
        in_target && /^    dependencies:/ { exit }
    ' "$spec"
}
host_profile_name=$(profile_name "$METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH")
keyboard_profile_name=$(profile_name "$METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH")
configured_host_profile_name=$(configured_profile_name app.msime.ios)
configured_keyboard_profile_name=$(configured_profile_name app.msime.ios.keyboard)
generated_project="$build_root/MetasequoiaImeIOS.xcodeproj/project.pbxproj"
replace_profile_name() {
    local configured_name=$1
    local actual_name=$2
    if [[ -z "$configured_name" || -z "$actual_name" ]]; then
        printf '%s\n' 'Could not determine an iOS provisioning profile name.' >&2
        exit 1
    fi
    if [[ "$configured_name" != "$actual_name" ]]; then
        OLD_PROFILE_NAME="$configured_name" NEW_PROFILE_NAME="$actual_name" \
            perl -0pi -e 's/\Q$ENV{OLD_PROFILE_NAME}\E/$ENV{NEW_PROFILE_NAME}/g' "$generated_project"
    fi
}
replace_profile_name "$configured_host_profile_name" "$host_profile_name"
replace_profile_name "$configured_keyboard_profile_name" "$keyboard_profile_name"

# Install the exact distribution profiles selected by the Release configuration. Xcode's cloud
# signing fallback can select a development profile for an automatic archive, which then cannot be
# exported to TestFlight. The profiles are injected by the workflow and never committed.
profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profiles_dir"
for profile in \
    "$METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH" \
    "$METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH"; do
    uuid=$(security cms -D -i "$profile" | plutil -extract UUID raw -o - -)
    cp "$profile" "$profiles_dir/$uuid.mobileprovision"
done

archive_log="$build_root/archive.log"
set +e
xcodebuild archive \
    -project "$build_root/MetasequoiaImeIOS.xcodeproj" \
    -scheme MetasequoiaImeIOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$build_root/derived" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$version" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    DEVELOPMENT_TEAM="$METASEQUOIA_IOS_TEAM_ID" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$METASEQUOIA_IOS_AUTH_KEY_PATH" \
    -authenticationKeyID "$METASEQUOIA_IOS_AUTH_KEY_ID" \
    -authenticationKeyIssuerID "$METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID" 2>&1 | tee "$archive_log"
archive_status=${PIPESTATUS[0]}
set -e
if [[ "$archive_status" -ne 0 ]]; then
    exit "$archive_status"
fi

application="$archive_path/Products/Applications/MetasequoiaIME.app"
extension="$application/PlugIns/MetasequoiaKeyboard.appex"
if [[ ! -d "$application" || ! -d "$extension" ]]; then
    printf '%s\n' 'Signed archive is missing the host application or keyboard extension.' >&2
    exit 1
fi

export_options="$build_root/ExportOptions.plist"
cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>teamID</key>
    <string>$METASEQUOIA_IOS_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

export_log="$build_root/export.log"
set +e
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$METASEQUOIA_IOS_AUTH_KEY_PATH" \
    -authenticationKeyID "$METASEQUOIA_IOS_AUTH_KEY_ID" \
    -authenticationKeyIssuerID "$METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID" 2>&1 | tee "$export_log"
export_status=${PIPESTATUS[0]}
set -e
if [[ "$export_status" -ne 0 ]]; then
    exit "$export_status"
fi

ipa=$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)
if [[ -z "$ipa" ]]; then
    printf '%s\n' 'Xcode export did not produce an IPA.' >&2
    exit 1
fi

if [[ -n "${METASEQUOIA_IOS_RELEASE_DIR:-}" ]]; then
    release_dir=$(cd "$METASEQUOIA_IOS_RELEASE_DIR" && pwd)
    signed_archive="$release_dir/MetasequoiaIME-$tag_name-ios-testflight.xcarchive.zip"
    signed_ipa="$release_dir/MetasequoiaIME-$tag_name-ios-testflight.ipa"
    ditto -c -k --keepParent "$archive_path" "$signed_archive"
    cp "$ipa" "$signed_ipa"
    (
        cd "$release_dir"
        shasum -a 256 "$(basename "$signed_archive")" > "$(basename "$signed_archive").sha256"
        shasum -a 256 "$(basename "$signed_ipa")" > "$(basename "$signed_ipa").sha256"
    )
fi

xcrun altool \
    --upload-app \
    --file "$ipa" \
    --type ios \
    --api-key "$METASEQUOIA_IOS_AUTH_KEY_ID" \
    --api-issuer "$METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID" \
    --p8-file-path "$METASEQUOIA_IOS_AUTH_KEY_PATH"

printf 'Uploaded %s to TestFlight.\n' "$tag_name"
