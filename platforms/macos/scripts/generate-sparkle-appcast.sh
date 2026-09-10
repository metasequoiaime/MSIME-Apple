#!/bin/bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY is required}"
: "${SPARKLE_TOOLS_DIR:?SPARKLE_TOOLS_DIR is required}"

tag_name=${1:-}
archive_path=${2:-}
output_path=${3:-}

if [[ ! "$tag_name" =~ ^(macos-|ios-)?v[0-9]+\.[0-9]+\.[0-9]+(-build\.[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2})?$ ]]; then
    printf '%s\n' "Tag must use vMAJOR.MINOR.PATCH with an optional -build.X.Y.Z suffix." >&2
    exit 1
fi
if [[ -z "$archive_path" || ! -f "$archive_path" ]]; then
    printf 'Sparkle update archive is missing: %s\n' "$archive_path" >&2
    exit 1
fi
if [[ -z "$output_path" ]]; then
    printf '%s\n' "Appcast output path is required." >&2
    exit 1
fi

# A single-platform build carries its platform ahead of the v, so it has to come off before the
# version does: ${tag_name#v} alone would leave macos-v0.48.6 and ship that as a version.
version=${tag_name#macos-}
version=${version#ios-}
version=${version#v}
build_number=${METASEQUOIA_BUILD_NUMBER:-$version}
if [[ "$tag_name" == *-build.* ]]; then
    build_number=${tag_name##*-build.}
fi

archive_name=$(basename "$archive_path")
case "$archive_name" in
    "MetasequoiaIME-$tag_name-macos-universal-update.zip" | \
        "MetasequoiaIME-$tag_name-macos-universal-unsigned-update.zip") ;;
    *)
        printf 'Update archive does not match release tag %s: %s\n' "$tag_name" "$archive_name" >&2
        exit 1
        ;;
esac

generate_appcast="$SPARKLE_TOOLS_DIR/generate_appcast"
sign_update="$SPARKLE_TOOLS_DIR/sign_update"
for tool in "$generate_appcast" "$sign_update"; do
    if [[ ! -x "$tool" ]]; then
        printf 'Sparkle tool is missing or not executable: %s\n' "$tool" >&2
        exit 1
    fi
done

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/metasequoia-appcast.XXXXXX")
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

archives_dir="$temporary_root/archives"
unsigned_appcast="$archives_dir/appcast.xml"
mkdir -p "$archives_dir" "$(dirname "$output_path")"
cp "$archive_path" "$archives_dir/$archive_name"

download_prefix="https://github.com/$GH_REPO/releases/download/$tag_name/"
product_link="https://github.com/$GH_REPO/releases/tag/$tag_name"
(
    cd "$archives_dir"
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$generate_appcast" \
        --ed-key-file - \
        --download-url-prefix "$download_prefix" \
        --link "$product_link" \
        --versions "$build_number" \
        --maximum-deltas 0 \
        -o appcast.xml \
        .
)

if [[ ! -s "$unsigned_appcast" ]] || ! grep -Fq "$download_prefix$archive_name" "$unsigned_appcast" || \
    ! grep -Fq 'sparkle:edSignature=' "$unsigned_appcast"; then
    printf '%s\n' "Generated appcast is missing the trusted archive URL or EdDSA signature." >&2
    exit 1
fi

printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$unsigned_appcast"
mv -f "$unsigned_appcast" "$output_path"
printf '%s\n' "$output_path"
