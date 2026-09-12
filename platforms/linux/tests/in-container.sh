#!/usr/bin/env bash
set -euo pipefail
[[ ${MSIME_ISOLATED_LINUX_TEST:-} == 1 && -d /resources && -d /build ]] || exit 2
python3 platforms/linux/tests/panel_keymap.py
cargo build -p msime-host-api --locked
python3 - <<'PY'
import ctypes
import re
from pathlib import Path

header = Path("crates/host-api/include/msime_client.h").read_text()
library = ctypes.CDLL("/build/cargo/debug/libmsime_host_api.so")
symbols = set(re.findall(r"\b(msime_client_\w+)\s*\(", header))
assert symbols, "Host API header contains no exported declarations"
for name in sorted(symbols):
    getattr(library, name)
print("Host API header exports verified")
PY
cargo test -p msime-client-core -p msime-input-runtime -p msime-host-api --locked
cmake -S platforms/linux -B /build/ibus -G Ninja -DMSIME_HOST_LIBRARY=/build/cargo/debug/libmsime_host_api.so -DMSIME_LINUX_VOICE=ON
cmake --build /build/ibus
ctest --test-dir /build/ibus --output-on-failure --no-tests=error
rm -rf /build/stage
DESTDIR=/build/stage cmake --install /build/ibus
test -x /build/stage/usr/local/bin/msime-client-ibus
test -x /build/stage/usr/local/bin/msime-client-dictionary
test -x /build/stage/usr/local/bin/msime-client-cloud-dictionary
test -x /build/stage/usr/local/bin/msime-client-cloud-clipboard
test -x /build/stage/usr/local/bin/msime-client-voice
test -f /build/stage/usr/local/share/ibus/component/msime-client-preview.xml
grep -q '/usr/local/etc/msime-client/runtime-options.json' \
  /build/stage/usr/local/share/ibus/component/msime-client-preview.xml
python3 platforms/linux/tests/dictionary_smoke.py /build/ibus/msime-client-dictionary /build/cargo/debug/libmsime_host_api.so /resources
clipboard_fixture=$(mktemp -d /tmp/msime-clipboard.XXXXXX)
trap 'rm -rf "$clipboard_fixture"' EXIT
/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" add $'first\nentry'
/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" add "second"
[[ $(stat -c '%a' "$clipboard_fixture/history.json") == 600 ]]
[[ $(stat -c '%a' "$clipboard_fixture/history.json.lock") == 600 ]]
! compgen -G "$clipboard_fixture/history.json.tmp.*" >/dev/null
[[ $(/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" get 1) == $'first\nentry' ]]
if /build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" get 2 >/dev/null; then
  echo "clipboard get accepted an out-of-range index" >&2
  exit 1
fi
echo "Linux clipboard stream acceptance passed"
unicode_text='水杉输入法 😀'
/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" add "$unicode_text"
[[ $(/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" get 0) == "$unicode_text" ]]
echo "Linux clipboard UTF-8 acceptance passed"
/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" remove-index 0
[[ $(/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" get 0) == "second" ]]
echo "Linux clipboard remove-index acceptance passed"
/build/stage/usr/local/bin/msime-client-clipboard "$clipboard_fixture/history.json" clear
[[ ! -e "$clipboard_fixture/history.json" ]]
echo "Linux clipboard clear acceptance passed"
/build/ibus/ibus-engine-smoke /resources
installed_host=/build/stage/usr/local/bin/msime-client-ibus
python3 - "$installed_host" <<'PYTHON'
import re
import subprocess
import sys
from pathlib import Path

output = subprocess.check_output(["ldd", sys.argv[1]], text=True)
match = re.search(r"libmsime_host_api\.so => (\S+)", output)
expected = Path("/build/stage/usr/local/lib/msime-client/libmsime_host_api.so")
assert match and Path(match[1]).resolve() == expected.resolve(), \
    "Installed host did not resolve the staged Host API library"
print("Installed host resolves staged Host API library")
PYTHON
fixture=$(mktemp -d /tmp/msime-ibus-bootstrap.XXXXXX)
options=$(cargo run --quiet -p msime-host-api --example prepare_host --locked -- /resources "$fixture")
global_mode_options="$fixture/global-runtime-options.json"
python3 - "$options" "$global_mode_options" <<'PYTHON'
import json
import os
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text())
value["preferences"]["ime_mode_scope"] = "global"
value.pop("preferences_directory", None)
with os.fdopen(os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as output:
    json.dump(value, output)
PYTHON
dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh "$installed_host" "$global_mode_options"

GTK_IM_MODULE=ibus XMODIFIERS=@im=ibus NO_AT_BRIDGE=1 xvfb-run -a dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh "$installed_host" "$options" platforms/linux/tests/gtk_smoke.py

QT_IM_MODULE=ibus XMODIFIERS=@im=ibus xvfb-run -a dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh "$installed_host" "$options" platforms/linux/tests/qt_smoke.py

QT_IM_MODULE=ibus XMODIFIERS=@im=ibus xvfb-run -a dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh "$installed_host" "$options" platforms/linux/tests/qt_smoke.py --qt6

XCOMPOSEFILE="$PWD/platforms/linux/tests/compose.fixture" GTK_IM_MODULE=ibus XMODIFIERS=@im=ibus NO_AT_BRIDGE=1 xvfb-run -a dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh "$installed_host" "$options" platforms/linux/tests/gtk_smoke.py --custom-compose

runuser -u nobody -- dbus-run-session -- bash platforms/linux/tests/wayland_smoke.sh "$installed_host" /resources /build/cargo/debug/examples/prepare_host

runuser -u nobody -- dbus-run-session -- bash platforms/linux/tests/wayland_smoke.sh "$installed_host" /resources /build/cargo/debug/examples/prepare_host platforms/linux/tests/qt_smoke.py --wayland
runuser -u nobody -- dbus-run-session -- bash platforms/linux/tests/wayland_smoke.sh "$installed_host" /resources /build/cargo/debug/examples/prepare_host platforms/linux/tests/qt_smoke.py --wayland --qt6

runuser -u nobody -- dbus-run-session -- bash platforms/linux/tests/wayland_smoke.sh "$installed_host" /resources /build/cargo/debug/examples/prepare_host platforms/linux/tests/portal_smoke.py
