#!/usr/bin/env bash
# Check the maintainer scripts inside a built msime-client .deb: prerm and postinst are present, executable (CPACK_DEBIAN_PACKAGE_CONTROL_STRICT_PERMISSION gives them 0755), and pass shellcheck as the POSIX sh they declare; and DEBIAN/conffiles lists exactly the files the package ships under /etc. Their behaviour per dpkg action is tested by tests/core/deb_maintainer_scripts.py in ctest; this proves CPack actually put them into the package.
#
# Usage: check-deb-maintainer-scripts.sh <msime-linux.deb>
# Needs dpkg-deb and shellcheck.
set -euo pipefail

[[ $# == 1 && -f $1 ]] || {
  echo "usage: check-deb-maintainer-scripts.sh <msime-linux.deb>" >&2
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
# Every file the package ships under /etc must be a conffile, or dpkg overwrites an administrator's edit or deletion on the next upgrade.
etc_files=$(dpkg-deb -c "$1" | awk '$1 !~ /^d/ { sub(/^\./, "", $6); print $6 }' | grep '^/etc/' | sort || :)
conffiles=$(sort "$control/DEBIAN/conffiles" 2>/dev/null || :)
[[ -n $etc_files ]] || { echo "$1 ships no file under /etc; expected the clipboard XDG autostart entry" >&2; exit 1; }
[[ $etc_files == "$conffiles" ]] || {
  printf '%s conffiles do not match its /etc files\nconffiles:\n%s\n/etc files:\n%s\n' "$1" "$conffiles" "$etc_files" >&2
  exit 1
}
echo "prerm and postinst are packaged, executable and pass shellcheck; every /etc file is a conffile"
