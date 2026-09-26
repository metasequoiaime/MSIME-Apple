#!/usr/bin/env python3
"""`fetch_engine.py --matches <vendor>` accepts only a tree prepared for this checkout's exact lock, and `--borrowable` finds such a tree in this checkout or the main one.

The Linux container gates borrow the main checkout's vendor/ so a worktree need not fetch 322 MB of its own. They used to accept any directory that existed. On 2026-09-23 the main checkout's tree was at the locked Engine commit but predated an overlay script, and every worktree gate failed in bridge.cpp on a missing Engine symbol that looked exactly like a code break. The marker records the overlay scripts by content, so comparing it is what tells the two trees apart.
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
FETCH = ROOT / "scripts/fetch_engine.py"
sys.path.insert(0, str(ROOT / "scripts"))

import fetch_engine  # noqa: E402


def matches(vendor: pathlib.Path) -> bool:
    return subprocess.run([sys.executable, str(FETCH), "--matches", str(vendor)], cwd=ROOT).returncode == 0


def prepare(vendor: pathlib.Path, marker: str, lock: dict) -> pathlib.Path:
    engine = vendor / "MSIME-Engine"
    for dependency in lock["dependencies"]:
        (engine / dependency["path"]).mkdir(parents=True, exist_ok=True)
    (engine / ".msime-engine-lock").write_text(marker, encoding="utf-8")
    return engine


def git(*args: str) -> None:
    subprocess.run(["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)


def check_borrowable(base: pathlib.Path, current: str, lock: dict, failures: list) -> None:
    """`--borrowable` prefers this checkout's own tree, falls back to the main worktree's, and returns nothing when neither matches."""
    main_checkout = base / "main-checkout"
    worktree = base / "worktree"
    git("init", "-q", str(main_checkout))
    git("-C", str(main_checkout), "commit", "-q", "--allow-empty", "-m", "init")
    git("-C", str(main_checkout), "worktree", "add", "-q", "--detach", str(worktree))

    if fetch_engine.borrowable(lock, worktree) is not None:
        failures.append("--borrowable returned a tree when neither checkout has one")

    main_engine = prepare(main_checkout / "vendor", current.replace(lock["commit"], "0" * 40, 1), lock)
    if fetch_engine.borrowable(lock, worktree) is not None:
        failures.append("--borrowable returned the main checkout's tree prepared for another lock")

    (main_engine / ".msime-engine-lock").write_text(current, encoding="utf-8")
    if fetch_engine.borrowable(lock, worktree) != (main_checkout / "vendor").resolve():
        failures.append("--borrowable did not fall back to the main checkout's matching tree")

    prepare(worktree / "vendor", current, lock)
    if fetch_engine.borrowable(lock, worktree) != (worktree / "vendor").resolve():
        failures.append("--borrowable did not prefer this checkout's own matching tree")


def main() -> int:
    lock = json.loads((ROOT / "engine-lock.json").read_text(encoding="utf-8"))
    current = fetch_engine.lock_marker(lock)
    failures = []
    with tempfile.TemporaryDirectory() as directory:
        base = pathlib.Path(directory)

        exact = base / "exact"
        prepare(exact, current, lock)
        if not matches(exact):
            failures.append("a tree carrying this checkout's marker was rejected")

        commit, overlays = current.split("\n", 1)
        stale_overlays = json.loads(overlays)
        first = next(iter(stale_overlays["scripts"]), None)
        if first is not None:
            stale_overlays["scripts"][first] = "0" * 64
            stale = base / "stale-overlay"
            prepare(stale, f"{commit}\n{json.dumps(stale_overlays, sort_keys=True, separators=(',', ':'))}", lock)
            if matches(stale):
                failures.append("a tree at the locked commit with an older overlay was accepted")

        other = base / "other-commit"
        prepare(other, current.replace(lock["commit"], "0" * 40, 1), lock)
        if matches(other):
            failures.append("a tree at another Engine commit was accepted")

        missing = base / "missing-dependency"
        engine = prepare(missing, current, lock)
        if lock["dependencies"]:
            (engine / lock["dependencies"][0]["path"]).rmdir()
            if matches(missing):
                failures.append("a tree missing a locked dependency was accepted")

        if matches(base / "absent"):
            failures.append("a directory without MSIME-Engine was accepted")

        check_borrowable(base, current, lock, failures)

    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print("fetch_engine --matches and --borrowable accept only this checkout's lock")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
