#!/usr/bin/env bash
set -euo pipefail

# Produces the iOS release artifact: an unsigned .xcarchive, zipped, with a checksum manifest.
#
# It is unsigned because this repository has no Apple signing identity configured — the same reason
# every macOS release so far is the unsigned variant. An unsigned archive is not installable: iOS
# has no equivalent of "allow it in Privacy & Security", and a custom keyboard reaches users only
# through the App Store or TestFlight. What this artifact is for is re-signing: a maintainer with a
# Developer Program membership can export an IPA from it without rebuilding, so the bits that ship
# are the bits this tag built and tested. When signing secrets do exist, the export step belongs
# here next to the archive, not in a separate rebuild.

project_root=${METASEQUOIA_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
project_root=$(cd "$project_root" && pwd)

tag_name=${1:-}
output_dir=${2:-$project_root/dist}
# The IPA is created from inside its staged Payload directory below. Resolve caller-supplied
# relative paths before entering that directory, otherwise `dist/foo.ipa` is looked up under the
# staging tree instead of the repository checkout.
if [[ "$output_dir" != /* ]]; then
    output_dir="$(pwd)/$output_dir"
fi

if [[ ! "$tag_name" =~ ^(macos-|ios-)?v[0-9]+\.[0-9]+\.[0-9]+(-build\.[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2})?$ ]]; then
    printf '%s\n' "Tag must use vMAJOR.MINOR.PATCH with an optional -build.X.Y.Z suffix." >&2
    exit 1
fi
# A single-platform build carries its platform ahead of the v, so it has to come off before the
# version does: ${tag_name#v} alone would leave macos-v0.48.6 and ship that as a version.
version=${tag_name#macos-}
version=${version#ios-}
version=${version#v}
version=${version%%-build.*}

for tool in git pod xcodegen xcodebuild ditto shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required tool is missing: %s\n' "$tool" >&2
        exit 1
    fi
done

# This archive is what a maintainer opens in Xcode Organizer to push to TestFlight, so it needs the
# same build number rule as the signed path: unique and increasing within one marketing version,
# rather than a copy of the marketing version that allows only one build per release.
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

spec="$project_root/platforms/ios/project.yml"
if [[ ! -f "$spec" ]]; then
    printf 'iOS project spec not found at %s\n' "$spec" >&2
    exit 1
fi

# The keyboard extension lists the compact dictionary as a build resource, so a missing database is
# an xcodebuild failure several minutes in rather than an obvious one here.
dictionary="$project_root/platforms/ios/KeyboardExtension/Resources/msime.db"
if [[ ! -s "$dictionary" ]]; then
    printf 'iOS dictionary not found at %s. Run platforms/ios/scripts/prepare_dictionary.py first.\n' "$dictionary" >&2
    exit 1
fi

# project.yml resolves every source and Info.plist path as $(PROJECT_DIR)/../../..., so the generated
# project has to sit exactly two levels below the repository root or the build fails on a missing
# bridging header. CI generates into build/ios for the same reason; keep this at the same depth.
build_root="$project_root/build/ios-release"
archive_path="$build_root/MetasequoiaIME.xcarchive"
rm -rf -- "$build_root"
mkdir -p "$build_root" "$output_dir"

xcodegen generate --spec "$spec" --project "$build_root" --project-root "$project_root"
MSIME_IOS_BUILD_ROOT="$build_root" pod install --deployment --project-directory="$project_root/platforms/ios"

# MARKETING_VERSION is passed on the command line as well as being bumped in project.yml, so the
# archive carries the release version even when the spec is momentarily behind the tag being built.
xcodebuild archive \
    -workspace "$build_root/MetasequoiaImeIOS.xcworkspace" \
    -scheme MetasequoiaImeIOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$build_root/derived" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS=""

application="$archive_path/Products/Applications/MetasequoiaIME.app"
extension="$application/PlugIns/MetasequoiaKeyboard.appex"
if [[ ! -d "$application" ]]; then
    printf 'Archive is missing the host application: %s\n' "$application" >&2
    exit 1
fi
# The whole point of the iOS build is the keyboard. An archive that dropped the extension would
# still look like a successful build.
if [[ ! -d "$extension" ]]; then
    printf 'Archive is missing the keyboard extension: %s\n' "$extension" >&2
    exit 1
fi
if [[ ! -s "$extension/msime.db" ]]; then
    printf 'Archive is missing the packaged dictionary inside the keyboard extension.\n' >&2
    exit 1
fi

# Verify both targets before distributing the archive.
for bundle in "$archive_path/Products/Applications/MetasequoiaIME.app" \
    "$archive_path/Products/Applications/MetasequoiaIME.app/PlugIns/MetasequoiaKeyboard.appex"; do
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Info.plist")" = "$build_number"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Info.plist")" = "$version"
done

archive_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Info.plist")
if [[ "$archive_version" != "$version" ]]; then
    printf 'Archive version %s does not match tag %s.\n' "$archive_version" "$tag_name" >&2
    exit 1
fi
extension_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extension/Info.plist")
if [[ "$extension_version" != "$version" ]]; then
    printf 'Keyboard extension version %s does not match tag %s.\n' "$extension_version" "$tag_name" >&2
    exit 1
fi

bundle="$output_dir/MetasequoiaIME-$tag_name-ios-unsigned.xcarchive.zip"
rm -f -- "$bundle" "$bundle.sha256"
ditto -c -k --keepParent "$archive_path" "$bundle"

# The .ipa is the artifact anyone other than the maintainer can actually use. Re-signing tools take
# an .ipa directly and sign it with the user's own Apple ID; exporting from the .xcarchive instead
# needs Xcode's Organizer and a Developer Program membership. An .ipa is just a zip whose top-level
# directory is Payload, so it needs no signing identity to produce — the payload inside is unsigned
# and has to be re-signed before a device will run it.
payload_root="$build_root/ipa"
rm -rf -- "$payload_root"
mkdir -p "$payload_root/Payload"
cp -R "$application" "$payload_root/Payload/"
# Checked on the staged tree rather than by grepping a listing of the finished zip: the payload is
# what this script controls, and a test that parses another tool's output can fail for reasons that
# have nothing to do with the payload being wrong.
staged_extension="$payload_root/Payload/MetasequoiaIME.app/PlugIns/MetasequoiaKeyboard.appex"
if [[ ! -x "$staged_extension/MetasequoiaKeyboard" || ! -s "$staged_extension/msime.db" ]]; then
    printf 'The staged .ipa payload is missing the keyboard extension or its dictionary.\n' >&2
    exit 1
fi

ipa="$output_dir/MetasequoiaIME-$tag_name-ios-unsigned.ipa"
rm -f -- "$ipa" "$ipa.sha256"
# zip rather than ditto: ditto writes AppleDouble ._ entries beside the payload, and an .ipa is
# consumed by tools that do not expect them.
(cd "$payload_root" && zip -qry "$ipa" Payload)
# Reads the whole archive back and verifies every CRC, so a truncated or corrupt .ipa cannot ship.
unzip -tqq "$ipa"

(
    cd "$output_dir"
    for artifact in "$bundle" "$ipa"; do
        shasum -a 256 "$(basename "$artifact")" > "$(basename "$artifact").sha256"
    done
)
printf '%s\n%s\n' "$bundle" "$ipa"
