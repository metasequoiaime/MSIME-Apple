#!/usr/bin/env bash
set -euo pipefail
[[ ${MSIME_ISOLATED_LINUX_TEST:-} == 1 && -d /resources && -d /build ]] || exit 2
cargo build -p msime-host-api --locked
cargo test -p msime-client-core -p msime-input-runtime -p msime-host-api --locked
cmake -S platforms/linux -B /build/ibus -G Ninja -DMSIME_HOST_LIBRARY=/build/cargo/debug/libmsime_host_api.so
cmake --build /build/ibus
python3 platforms/linux/tests/dictionary_smoke.py /build/ibus/msime-client-dictionary /build/cargo/debug/libmsime_host_api.so /resources
/build/ibus/ibus-engine-smoke /resources
fixture=$(mktemp -d /tmp/msime-ibus-bootstrap.XXXXXX)
options=$(cargo run --quiet -p msime-host-api --example prepare_host --locked -- /resources "$fixture")
dbus-run-session -- bash platforms/linux/tests/daemon_smoke.sh /build/ibus/msime-client-ibus "$options"
