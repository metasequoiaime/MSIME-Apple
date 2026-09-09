#!/usr/bin/env bash
# Prepare only this repo's default cache; never reset an existing checkout.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
tooling="$repo_root/target/tooling"
destination="$tooling/vcpkg"
revision=ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0
mkdir -p "$tooling"
lock="$tooling/vcpkg-bootstrap.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "vcpkg bootstrap lock exists; inspect the prior process before removing the empty lock directory" >&2
  exit 1
fi
trap 'rmdir "$lock"' EXIT
if [[ -e "$destination" || -L "$destination" ]]; then
  [[ ! -L "$destination" && -d "$destination/.git" ]] || { echo "Refusing an unexpected vcpkg cache" >&2; exit 1; }
  [[ $(git -C "$destination" rev-parse HEAD) = "$revision" ]] || { echo "Existing vcpkg revision differs; leave it untouched" >&2; exit 1; }
  git -C "$destination" diff --quiet HEAD -- || { echo "Existing vcpkg has tracked changes; leave it untouched" >&2; exit 1; }
  if [[ ! -x "$destination/vcpkg" ]]; then
    (cd "$destination" && ./bootstrap-vcpkg.sh -disableMetrics)
  fi
else
  staging=$(mktemp -d "$tooling/vcpkg.incoming.XXXXXX")
  # Failed preparations remain isolated for diagnosis; no recursive cleanup.
  echo "Preparing pinned vcpkg in $staging"
  git -C "$staging" init -q
  git -C "$staging" remote add origin https://github.com/microsoft/vcpkg.git
  git -C "$staging" fetch --depth 1 origin "$revision"
  git -C "$staging" checkout --detach FETCH_HEAD
  [[ $(git -C "$staging" rev-parse HEAD) = "$revision" ]]
  (cd "$staging" && ./bootstrap-vcpkg.sh -disableMetrics)
  # Do not replace a cache created by another actor outside this lock.
  [[ ! -e "$destination" && ! -L "$destination" ]] || { echo "vcpkg destination appeared during preparation" >&2; exit 1; }
  mv -n "$staging" "$destination"
  [[ ! -d "$staging" ]] || { echo "vcpkg destination changed during publication" >&2; exit 1; }
fi
[[ -d "$destination/.git" && ! -L "$destination" ]]
[[ $(git -C "$destination" rev-parse HEAD) = "$revision" ]]
[[ -x "$destination/vcpkg" ]]
echo "Pinned vcpkg ready: $revision"
