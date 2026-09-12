#!/usr/bin/env bash
set -euo pipefail
[[ ${MSIME_ISOLATED_LINUX_TEST:-} == 1 && $(id -u) != 0 ]] || exit 2
runtime=$(mktemp -d /tmp/msime-wayland.XXXXXX)
chmod 700 "$runtime"
export XDG_RUNTIME_DIR="$runtime"
export XDG_CACHE_HOME="$runtime/cache" XDG_CONFIG_HOME="$runtime/config"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
unset DISPLAY
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
compositor_pid=
cleanup() {
  if [[ -n "$compositor_pid" ]]; then kill "$compositor_pid" 2>/dev/null || true; wait "$compositor_pid" 2>/dev/null || true; fi
  rm -rf "$runtime"
}
trap cleanup EXIT
options=$("${3:?prepare-host executable required}" "${2:?resources required}" "$runtime/profile")
sway -c platforms/linux/tests/sway-test.conf > "$runtime/sway.log" 2>&1 &
compositor_pid=$!
for attempt in $(seq 1 100); do
  for socket in "$runtime"/wayland-*; do
    if [[ -S "$socket" ]]; then export WAYLAND_DISPLAY="${socket##*/}"; break 2; fi
  done
  kill -0 "$compositor_pid"
  sleep 0.05
done
[[ -n ${WAYLAND_DISPLAY:-} ]] || exit 1
GDK_BACKEND=wayland GTK_IM_MODULE=ibus NO_AT_BRIDGE=1 bash platforms/linux/tests/daemon_smoke.sh "$1" "$options" platforms/linux/tests/wayland_smoke.py
