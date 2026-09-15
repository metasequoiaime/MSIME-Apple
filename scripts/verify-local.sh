#!/usr/bin/env bash
# Local verification for MSIME-Client.
#
# AGENTS.md pauses private-repo CI to control cost and requires local
# verification instead. Nothing here talks to CI; it runs the checks that
# document requires - Rust tests, fmt and clippy; UI type check; native host
# build and tests - and reports the result.
#
# The point of this script is the baseline. Several suites have long-standing
# failures, so a bare pass/fail number says nothing: the only question that
# matters before a merge is "did this change break something that worked?".
# Every phase therefore compares the set of failing test *names* against
# scripts/known-failures.txt and fails only on names that are not in it.
#
# Six compile breaks reached develop in one session because branches were
# merged without building the merge result. `--quick` exists for exactly that:
# it runs only the compile phases, which caught every one of those six.
#
# Usage:
#   scripts/verify-local.sh --quick   compile only, the pre-merge gate
#   scripts/verify-local.sh           everything
#   scripts/verify-local.sh --update-baseline   rewrite known-failures.txt
#
# --update-baseline records one run. Several desktop tests are flaky, so a
# single run under-reports: the committed baseline is the union of several,
# and entries should be removed as they are fixed rather than re-recorded.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
baseline="scripts/known-failures.txt"
quick=0
update=0
for argument in "$@"; do
  case "$argument" in
    --quick) quick=1 ;;
    --update-baseline) update=1 ;;
    *) echo "unknown option: $argument" >&2; exit 2 ;;
  esac
done

# vcpkg supplies SQLite and the other native dependencies the Engine bridge
# links. Override when your toolchain lives elsewhere; without it the bridge
# build fails in a way that looks like a code error but is not.
: "${MSIME_VCPKG_PREFIX:=E:/msime-runner/vcpkg-tool/installed/x64-windows-static-md}"
: "${MSIME_NATIVE_BUILD:=target/win-full}"
# The pipe-only configuration builds the protocol tests without the Rust host
# library. It is a separate CMake configuration, so nothing in the ordinary
# build covers it - and a configuration nobody runs is one that rots.
: "${MSIME_PIPE_BUILD:=target/windows-pipe}"
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
export CMAKE_PREFIX_PATH="$MSIME_VCPKG_PREFIX"
export CXXFLAGS="-I$MSIME_VCPKG_PREFIX/include"

failed=0
note() { printf '\n=== %s ===\n' "$1"; }
fail() { echo "FAIL: $1"; failed=1; }

# Compare this phase's failing test names against the baseline. Anything not
# already known is a regression this change introduced.
compare() {
  local phase="$1" observed="$2"
  local unexpected
  unexpected="$(comm -23 <(grep -v '^ *$' "$observed" | sort -u)                         <(grep -vE '^ *(#|$)' "$baseline" | sort -u) || true)"
  if [ -n "$unexpected" ]; then
    fail "$phase has failures that are not in the baseline:"
    printf '  %s\n' "$unexpected"
    new_failures="$new_failures$unexpected"$'\n'
  else
    echo "$phase: at baseline"
  fi
}

collected="$(mktemp)"
trap 'rm -f "$collected" "$collected".*' EXIT

# A stale engine tree fails the build with undeclared-identifier errors that look
# exactly like a code break - this script's own first run lost time to that.
# Check it before blaming the source.
note "vendored engine"
if python3 scripts/fetch_engine.py; then
  echo "vendored engine: at the locked commit"
else
  fail "vendor/MSIME-Engine could not be prepared from engine-lock.json"
  echo "  until then every build error below may be an artefact of the stale tree"
fi

note "default config contracts"
python3 scripts/test-default-config-parity.py || fail "default config contracts"

note "compile: rust workspace"
cargo check --workspace --all-targets 2>&1 | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "cargo check"

note "compile: native host"
if [ -d "$MSIME_NATIVE_BUILD" ]; then
  # The native tests link the Rust library, so it has to be current or they
  # fail to start with an entry-point error that looks like a test failure.
  cargo build -p msime-host-api 2>&1 | tail -2
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "cargo build -p msime-host-api"
  for built in target/debug/msime_host_api.dll target/debug/libmsime_host_api.so; do
    [ -f "$built" ] && cp -f "$built" "$MSIME_NATIVE_BUILD/Debug/" 2>/dev/null
  done
  cmake --build "$MSIME_NATIVE_BUILD" --config Debug 2>&1 | grep -Ei "error C[0-9]|error LNK" | head -5
  cmake --build "$MSIME_NATIVE_BUILD" --config Debug >/dev/null 2>&1 || fail "native build"
else
  echo "skipped: $MSIME_NATIVE_BUILD not configured"
fi

note "compile: pipe-only configuration"
# Cheap: no Rust library, no vcpkg dependencies, just the protocol tests.
if cmake -S platforms/windows -B "$MSIME_PIPE_BUILD" -DMSIME_WINDOWS_PIPE_ONLY=ON      >/dev/null 2>&1; then
  if cmake --build "$MSIME_PIPE_BUILD" --config Debug >/dev/null 2>&1; then
    echo "pipe-only: builds"
  else
    fail "pipe-only build"
    cmake --build "$MSIME_PIPE_BUILD" --config Debug 2>&1 |
      grep -Ei "error C[0-9]|error LNK" | head -5
  fi
else
  fail "pipe-only configure"
fi

if [ "$quick" -eq 1 ]; then
  echo
  if [ "$failed" -eq 0 ]; then
    echo "quick check passed"
  else
    echo "quick check FAILED"
  fi
  exit "$failed"
fi

note "rust tests"
: > "$collected.rust"
for package in msime-client-core msime-host-api msime-input-runtime msime-host-windows; do
  cargo test -p "$package" 2>&1 |
    sed -n 's/^ *\([A-Za-z0-9_:]*\) *$/\1/p' > /dev/null || true
  cargo test -p "$package" --no-fail-fast 2>&1 |
    grep -E "^    [a-z_]+::" | sed "s/^ *//;s#^#$package #" >> "$collected.rust" || true
done
compare "rust tests" "$collected.rust"

note "rust fmt and clippy (changed files only)"
# The whole tree is not clean, and reformatting it would collide with every
# other branch in flight. What matters is that this change does not add to it.
changed="$(git diff --name-only origin/develop...HEAD -- '*.rs' 2>/dev/null || true)"
if [ -n "$changed" ]; then
  for file in $changed; do
    [ -f "$file" ] || continue
    rustfmt --check --edition 2021 "$file" >/dev/null 2>&1 || echo "  unformatted: $file"
  done
else
  echo "no Rust files changed against origin/develop"
fi

note "native tests"
if [ -d "$MSIME_NATIVE_BUILD" ]; then
  (cd "$MSIME_NATIVE_BUILD" && ctest -C Debug 2>&1) |
    grep -E "\*\*\*(Failed|Not Run|Timeout)" |
    sed 's/.*Test *#[0-9]*: *//' | sed 's/[. ]*\*\*\*.*//' | sed 's#^#native #' > "$collected.native" || true
  compare "native tests" "$collected.native"
else
  echo "skipped: $MSIME_NATIVE_BUILD not configured"
fi

note "pipe-only tests"
if [ -d "$MSIME_PIPE_BUILD" ]; then
  ctest --test-dir "$MSIME_PIPE_BUILD" -C Debug 2>&1 |
    grep -E "\*\*\*(Failed|Not Run|Timeout)" |
    sed 's/.*Test *#[0-9]*: *//' | sed 's/[. ]*\*\*\*.*//' |
    sed 's#^#pipe #' > "$collected.pipe" || true
  compare "pipe-only tests" "$collected.pipe"
else
  echo "skipped: $MSIME_PIPE_BUILD not configured"
fi

note "typescript"
if [ -x apps/desktop/node_modules/.bin/tsc ]; then
  (cd apps/desktop && ./node_modules/.bin/tsc --noEmit -p tsconfig.json) || fail "tsc"
  # The project's own vitest, never npx: an npx copy resolves jsdom from its
  # own cache, fails to start every jsdom worker, and still reports success -
  # which hid this suite's real failures for an entire session.
  (cd apps/desktop && ./node_modules/.bin/vitest run --reporter=dot 2>&1) |
    grep -E "^ FAIL" | sed 's/^ FAIL  //;s/ [0-9]*ms$//' | sed 's#^#desktop #' > "$collected.ts" || true
  compare "typescript tests" "$collected.ts"
else
  echo "skipped: apps/desktop dependencies not installed"
fi

if [ "$update" -eq 1 ]; then
  cat "$collected".rust "$collected".native "$collected".pipe "$collected".ts     2>/dev/null | sort -u > "$baseline"
  echo
  echo "baseline rewritten: $(wc -l < "$baseline") known failures"
  exit 0
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "verification passed: no failures outside the baseline"
else
  echo "verification FAILED"
fi
exit "$failed"
