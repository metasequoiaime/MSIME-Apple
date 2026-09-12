#!/usr/bin/env bash
set -euo pipefail
[[ ${MSIME_ISOLATED_LINUX_TEST:-} == 1 ]] || { echo "Run only inside the dedicated Linux test container" >&2; exit 1; }
binary=${1:?host executable required}
options=${2:?runtime options required}
test_root=$(mktemp -d /tmp/msime-ibus-daemon.XXXXXX)
daemon_pid=
host_pid=
cleanup() {
  if [[ -n "$host_pid" ]]; then kill "$host_pid" 2>/dev/null || true; wait "$host_pid" 2>/dev/null || true; fi
  if [[ -n "$daemon_pid" ]]; then kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true; fi
  rmdir "$test_root" 2>/dev/null || true
}
trap cleanup EXIT
export IBUS_ADDRESS="unix:path=$test_root/bus"
ibus-daemon --single --panel disable --config disable --emoji-extension disable --address "$IBUS_ADDRESS" &
daemon_pid=$!
for attempt in $(seq 1 100); do
  [[ -S "$test_root/bus" ]] && break
  kill -0 "$daemon_pid"
  sleep 0.05
done
"$binary" "$options" &
host_pid=$!
/usr/bin/python3 "${3:-platforms/linux/tests/daemon_smoke.py}"
