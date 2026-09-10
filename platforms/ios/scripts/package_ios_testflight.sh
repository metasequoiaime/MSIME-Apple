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

if [[ ! "$tag_name" =~ ^(macos-|ios-)?v[0-9]+\.[0-9]+\.[0-9]+(-build\.[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2})?$ ]]; then
    printf '%s\n' 'Tag must use vMAJOR.MINOR.PATCH with an optional -build.X.Y.Z suffix.' >&2
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

for tool in git pod xcodegen xcodebuild xcrun; do
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

# A single-platform build carries its platform ahead of the v, so it has to come off before the
# version does: ${tag_name#v} alone would leave macos-v0.48.6 and ship that as a version.
version=${tag_name#macos-}
version=${version#ios-}
version=${version#v}
version=${version%%-build.*}

# CFBundleVersion has to be unique and strictly increasing within one CFBundleShortVersionString.
# Deriving it from the marketing version left exactly one possible build per release, so a build that
# failed Beta App Review could not be replaced without cutting another release -- and every new
# marketing version starts a fresh TestFlight version train that needs its own review. The commit
# count is monotonic and reproducible from the checkout alone.
# CI supplies the shared build. Keep commit-count builds for local legacy packaging.
if [[ -n "${METASEQUOIA_BUILD_NUMBER:-}" || "$tag_name" == *-build.* ]]; then
    build_number=${METASEQUOIA_BUILD_NUMBER:-}
    if [[ "$tag_name" == *-build.* ]]; then
        build_number=${tag_name##*-build.}
        if [[ "${METASEQUOIA_BUILD_NUMBER:-$build_number}" != "$build_number" ]]; then
            printf '%s\n' "Build number does not match release tag." >&2
            exit 1
        fi
    fi
else
    if ! git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'Not a git checkout, so the build number cannot be derived: %s\n' "$project_root" >&2
        exit 1
    fi
    if [[ "$(git -C "$project_root" rev-parse --is-shallow-repository)" == "true" ]]; then
        printf 'Refusing to build from a shallow checkout: the commit count would restart low and App Store Connect would reject the build as a downgrade. Check out with fetch-depth: 0.\n' >&2
        exit 1
    fi
    build_number=$(git -C "$project_root" rev-list --count HEAD)
fi

build_root="$project_root/build/ios-testflight"
archive_path="$build_root/MetasequoiaIME.xcarchive"
export_path="$build_root/export"
rm -rf -- "$build_root"
mkdir -p "$build_root" "$export_path"

xcodegen generate --spec "$spec" --project "$build_root" --project-root "$project_root"
MSIME_IOS_BUILD_ROOT="$build_root" pod install --deployment --project-directory="$project_root/platforms/ios"

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
host_profile_name=$(security cms -D -i "$METASEQUOIA_IOS_APP_PROVISIONING_PROFILE_PATH" | plutil -extract Name raw -o - -)
keyboard_profile_name=$(security cms -D -i "$METASEQUOIA_IOS_KEYBOARD_PROVISIONING_PROFILE_PATH" | plutil -extract Name raw -o - -)

archive_log="$build_root/archive.log"
set +e
xcodebuild archive \
    -workspace "$build_root/MetasequoiaImeIOS.xcworkspace" \
    -scheme MetasequoiaImeIOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$build_root/derived" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
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

# Verify both targets before distributing the archive.
for bundle in "$archive_path/Products/Applications/MetasequoiaIME.app" \
    "$archive_path/Products/Applications/MetasequoiaIME.app/PlugIns/MetasequoiaKeyboard.appex"; do
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Info.plist")" = "$build_number"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Info.plist")" = "$version"
done

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
    <key>provisioningProfiles</key>
    <dict>
        <key>app.msime.ios</key>
        <string>$host_profile_name</string>
        <key>app.msime.ios.keyboard</key>
        <string>$keyboard_profile_name</string>
    </dict>
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
    asset_tag=${tag_name#macos-}
    asset_tag=${asset_tag#ios-}
    signed_archive="$release_dir/MetasequoiaIME-$asset_tag-ios-testflight.xcarchive.zip"
    signed_ipa="$release_dir/MetasequoiaIME-$asset_tag-ios-testflight.ipa"
    ditto -c -k --keepParent "$archive_path" "$signed_archive"
    cp "$ipa" "$signed_ipa"
    (
        cd "$release_dir"
        shasum -a 256 "$(basename "$signed_archive")" > "$(basename "$signed_archive").sha256"
        shasum -a 256 "$(basename "$signed_ipa")" > "$(basename "$signed_ipa").sha256"
    )
fi

# Xcode 16 altool uses camel-case API options and discovers AuthKey_<ID>.p8 by directory.
private_keys_dir="$build_root/private_keys"
mkdir -p "$private_keys_dir"
chmod 700 "$private_keys_dir"
install -m 600 "$METASEQUOIA_IOS_AUTH_KEY_PATH" "$private_keys_dir/AuthKey_$METASEQUOIA_IOS_AUTH_KEY_ID.p8"
trap 'rm -rf -- "$private_keys_dir"' EXIT
API_PRIVATE_KEYS_DIR="$private_keys_dir" xcrun altool \
    --upload-app \
    --file "$ipa" \
    --type ios \
    --apiKey "$METASEQUOIA_IOS_AUTH_KEY_ID" \
    --apiIssuer "$METASEQUOIA_IOS_AUTH_KEY_ISSUER_ID"

printf 'Uploaded %s to TestFlight.\n' "$tag_name"
