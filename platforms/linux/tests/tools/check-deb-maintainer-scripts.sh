#!/usr/bin/env bash
# Check the maintainer scripts inside a built msime-client .deb: prerm and postinst are present, executable (CPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION gives them 0755), and pass shellcheck as the POSIX sh they declare. Their behaviour per dpkg action is tested by tests/core/deb_maintainer_scripts.py in ctest; this proves CPack actually put them into the package.
#
# Usage: check-deb-maintainer-scripts.sh <msime-client.deb>
# Needs dpkg-deb and shellcheck.
set -euo pipefail

[[ $# == 1 && -f $1 ]] || {
  echo "usage: check-deb-maintainer-scripts.sh <msime-client.deb>" >&2
  exit 2
}
control=$(mktemp -d)
trap 'rm -rf "$control"' EXIT
dpkg-deb -e "$1" "$control/DEBIAN"
for script in prerm postinst; do
  path="$control/DEBIAN/$script"
  [[ -f $path ]] || { echo "$1 has no $script" >&2; exit 1; }
  mode=$(stat -c '%a' "$path")
  [[ $mode == 755 ]] || { echo "$script in $1 has mode $mode, expected 755" >&2; exit 1; }
  [[ $(head -n 1 "$path") == '#!/bin/sh' ]] || { echo "$script in $1 is not a /bin/sh script" >&2; exit 1; }
done
shellcheck --shell=sh "$control/DEBIAN/prerm" "$control/DEBIAN/postinst"
echo "prerm and postinst are packaged, executable and pass shellcheck"
