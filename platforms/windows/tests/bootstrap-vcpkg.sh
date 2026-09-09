#!/usr/bin/env bash
# Offline rejection tests. Every target belongs to this fresh fixture tree.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "$repo_root/target"
scratch=$(mktemp -d "$repo_root/target/vcpkg-bootstrap-tests.XXXXXX")
for scenario in lock unexpected symlink revision; do
  fixture="$scratch/$scenario with spaces"
  mkdir -p "$fixture/platforms/windows" "$fixture/target/tooling"
  cp "$repo_root/platforms/windows/bootstrap-vcpkg.sh" "$fixture/platforms/windows/"
  cache="$fixture/target/tooling/vcpkg"
  case "$scenario" in
    lock) mkdir "$fixture/target/tooling/vcpkg-bootstrap.lock" ;;
    unexpected) mkdir "$cache" ;;
    symlink) ln -s "$fixture/platforms" "$cache" ;;
    revision)
      git -C "$fixture/target/tooling" init -q vcpkg
      git -C "$cache" -c user.name=Fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m fixture
      original=$(git -C "$cache" rev-parse HEAD)
      ;;
  esac
  if bash "$fixture/platforms/windows/bootstrap-vcpkg.sh"; then
    echo "Unexpected bootstrap success: $scenario" >&2
    exit 1
  fi
  case "$scenario" in
    lock) [[ -d "$fixture/target/tooling/vcpkg-bootstrap.lock" ]] ;;
    unexpected) [[ -d "$cache" && ! -e "$cache/.git" ]] ;;
    symlink) [[ -L "$cache" ]] ;;
    revision) [[ $(git -C "$cache" rev-parse HEAD) = "$original" ]] ;;
  esac
  [[ "$scenario" = lock || ! -e "$fixture/target/tooling/vcpkg-bootstrap.lock" ]]
done
echo "Offline vcpkg bootstrap rejection tests passed; fixtures retained in $scratch"
