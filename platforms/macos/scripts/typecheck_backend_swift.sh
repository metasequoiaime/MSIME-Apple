#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
backend_sources=$(find "$root/shared/backend" -maxdepth 1 -name '*.swift' ! -name 'Package.swift' -print)
backend_ui_sources=$(find "$root/shared/backend-ui" -maxdepth 1 -name '*.swift' -print)
mac_sources=$(find "$root/platforms/macos" -maxdepth 1 -name 'Backend*.swift' -print)

exec xcrun swiftc -typecheck -swift-version 5 -module-name MacBackendViews \
  $backend_sources $backend_ui_sources $mac_sources
