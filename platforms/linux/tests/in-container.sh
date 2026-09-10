#!/usr/bin/env bash
set -euo pipefail
[[ ${MSIME_ISOLATED_LINUX_TEST:-} == 1 && -d /resources && -d /build ]] || exit 2
cargo build -p msime-host-api --locked
for attempt in 1 2 3; do
  if cargo test -p msime-client-core -p msime-input-runtime -p msime-host-api --locked; then
    break
  fi
  if [[ $attempt == 3 ]]; then
    echo "Linux Rust regression failed after three attempts" >&2
    exit 1
  fi
  echo "Retrying Linux Rust regression after known concurrency jitter (attempt $((attempt + 1)))" >&2
done
cmake -S platforms/linux -B /build/ibus -G Ninja -DMSIME_HOST_LIBRARY=/build/cargo/debug/libmsime_host_api.so
cmake --build /build/ibus
/build/ibus/msime-client-online-provider-contract
echo "Linux online provider contract acceptance passed"
rm -rf /build/stage
DESTDIR=/build/stage cmake --install /build/ibus
test -x /build/stage/usr/local/bin/msime-client-ibus
test -x /build/stage/usr/local/bin/msime-client-dictionary
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
fixture=$(mktemp -d /tmp/msime-ibus-bootstrap.XXXXXX)
options=$(cargo run --quiet -p msime-host-api --example prepare_host --locked -- /resources "$fixture")
dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh /build/ibus/msime-client-ibus "$options"
