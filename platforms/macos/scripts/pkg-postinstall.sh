#!/bin/zsh
set -u

# Installer package scripts run as root. Register the input source in the
# logged-in user's GUI bootstrap session so TIS state is written to that
# user's profile instead of root's. A package install must still succeed when
# no GUI user is present (for example, during MDM deployment); the user can
# enable the source later from System Settings in that case.
console_user=$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)
if [[ -z "$console_user" || "$console_user" == root || "$console_user" == loginwindow ]]; then
    print -u2 "No logged-in GUI user; input source registration will be deferred."
    exit 0
fi

console_uid=$(/usr/bin/id -u "$console_user" 2>/dev/null || true)
if [[ -z "$console_uid" || ! "$console_uid" =~ '^[0-9]+$' || "$console_uid" -lt 501 ]]; then
    print -u2 "Could not resolve a normal GUI user; input source registration will be deferred."
    exit 0
fi

# The plist form rather than the plain one: dscl -read folds a value containing a space onto an
# indented continuation line, so awk '{print $2}' returned a fragment and the guard below rejected
# it. A relocated or directory-service-managed home on a path with a space then silently skipped
# registration, and the user had to enable the input source by hand.
user_home=$(/usr/bin/dscl -plist . -read "/Users/$console_user" NFSHomeDirectory 2>/dev/null |
    /usr/bin/xmllint --xpath 'string(//array/string[1])' - 2>/dev/null)
if [[ -z "$user_home" || "$user_home" != /* || "$user_home" == / ]]; then
    print -u2 "Could not resolve the GUI user's home directory; input source registration will be deferred."
    exit 0
fi

registration_command="$user_home/Library/Input Methods/MetasequoiaIME.app/Contents/MacOS/MetasequoiaIME"
if [[ ! -x "$registration_command" ]]; then
    print -u2 "Installed input method executable is missing; input source registration will be deferred."
    exit 0
fi

if ! /bin/launchctl asuser "$console_uid" /usr/bin/sudo -H -u "$console_user" -- \
    "$registration_command" --register-input-source; then
    print -u2 "Input source registration could not be completed automatically. Enable 水杉输入法 in System Settings > Keyboard > Text Input > Edit."
fi

exit 0
