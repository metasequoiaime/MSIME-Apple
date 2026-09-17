#!/usr/bin/env bash
# Local verification for MSIME-Client.
#
# AGENTS.md pauses private-repo CI to control cost and requires local
# verification instead. Nothing here talks to CI; it runs the checks that
# document requires - Rust tests, fmt, clippy and a dependency audit; UI type
# check; native host build and tests - and reports the result.
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
# platforms/macos was covered by nothing. It stopped compiling at some point and
# nobody found out, and the 103 tests behind that break had never reported at
# all. Configured directories only: the build needs a pinned Sparkle and a
# prepared engine state, so a machine without them skips this the way it already
# skips the Windows phases.
: "${MSIME_MACOS_BUILD:=target/macos-isolated}"
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
export CMAKE_PREFIX_PATH="$MSIME_VCPKG_PREFIX"
export CXXFLAGS="-I$MSIME_VCPKG_PREFIX/include"

windows_host=0
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) windows_host=1 ;; esac

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
# The desktop app's Tauri config lists the platform IME bundle as a packaged
# resource, and Tauri's build script fails when a listed resource is absent. On
# a checkout that has not built the native host yet that is not a code error, so
# it is skipped rather than reported as a broken workspace - the same treatment
# the native phases below already get.
desktop_resource="target/macos/MSIMEClientInputMethod.app"
[ "$windows_host" -eq 1 ] && desktop_resource="target/win-full"
if [ -e "$desktop_resource" ]; then
  cargo check --workspace --all-targets 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "cargo check"
else
  echo "msime-desktop: skipped ($desktop_resource not built yet)"
  cargo check --workspace --all-targets --exclude msime-desktop 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "cargo check"
fi

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

note "compile: macos"
if [ -d "$MSIME_MACOS_BUILD" ]; then
  cmake --build "$MSIME_MACOS_BUILD" --parallel 2>&1 | grep -E "error:|symbol\(s\) not found" | head -5
  cmake --build "$MSIME_MACOS_BUILD" --parallel >/dev/null 2>&1 || fail "macos build"
else
  echo "skipped: $MSIME_MACOS_BUILD not configured"
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
elif [ "$windows_host" -eq 0 ]; then
  # platforms/windows cannot configure off Windows, and this phase had no guard
  # for that while every other native phase does. --quick is documented as the
  # pre-merge gate, so an unconditional failure here made that gate permanently
  # red on macOS and Linux - which is a good way to teach everyone to skip it.
  echo "pipe-only: skipped (needs a Windows host)"
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

note "rust fmt (changed files only)"
# The whole tree is not clean, and reformatting it would collide with every
# other branch in flight. What matters is that this change does not add to it -
# so an unformatted file this change touched is a failure, not a printed note.
changed="$(git diff --name-only origin/develop...HEAD -- '*.rs' 2>/dev/null || true)"
if [ -n "$changed" ]; then
  unformatted=""
  for file in $changed; do
    [ -f "$file" ] || continue
    rustfmt --check --edition 2021 "$file" >/dev/null 2>&1 || unformatted="$unformatted  $file"$'\n'
  done
  if [ -n "$unformatted" ]; then
    fail "these changed files are not rustfmt-clean:"
    printf '%s' "$unformatted"
  else
    echo "changed Rust files: rustfmt-clean"
  fi
else
  echo "no Rust files changed against origin/develop"
fi

note "clippy: first-party crates"
# The header promised clippy for a long time without running it anywhere; the
# disabled CI workflow was the only place it had ever run. All seven crates
# under crates/ are clean at -D warnings today, so this is a hard gate with no
# baseline - if it starts failing, the change under test caused it.
#
# The workspace as a whole is not gated: apps/desktop needs a built frontend
# before its Tauri build script will run, which makes "clippy failed" and
# "frontend not built" indistinguishable on a developer machine.
clippy_failed=""
for crate in msime-client-core msime-engine-bridge msime-host-api msime-host-macos \
             msime-host-windows msime-input-runtime msime-tauri-mobile-platform; do
  cargo clippy -p "$crate" --all-targets -- -D warnings >/dev/null 2>&1 ||
    clippy_failed="$clippy_failed  $crate"$'\n'
done
if [ -n "$clippy_failed" ]; then
  fail "clippy -D warnings failed for:"
  printf '%s' "$clippy_failed"
else
  echo "first-party crates: clippy clean at -D warnings"
fi

note "dependency advisories"
# Lockfile-only, so it runs without building anything. A vulnerability is fatal;
# unmaintained and unsound advisories are accepted one at a time in
# .cargo/audit.toml, each with the chain that pulls it in and why - the same
# discipline as known-failures.txt, for the same reason.
#
# Not part of --quick: that gate has to work offline, and this fetches the
# advisory database.
if command -v cargo-audit >/dev/null 2>&1; then
  cargo audit 2>&1 | tail -3
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail "cargo audit"
else
  echo "cargo-audit not installed; skipping (cargo install cargo-audit)"
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

note "macos tests"
if [ -d "$MSIME_MACOS_BUILD" ]; then
  # The per-test lines put the reason between the dots and the ***, so this reads
  # the summary block instead: "\t 52 - local-mode-preferences (Subprocess aborted)".
  ctest --test-dir "$MSIME_MACOS_BUILD" 2>&1 |
    sed -n '/The following tests FAILED:/,$p' |
    sed -n 's/^[[:space:]]*[0-9][0-9]* - \([^ ]*\).*/macos \1/p' > "$collected.macos" || true
  compare "macos tests" "$collected.macos"
else
  echo "skipped: $MSIME_MACOS_BUILD not configured"
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
