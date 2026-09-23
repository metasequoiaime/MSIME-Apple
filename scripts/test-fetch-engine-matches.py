#!/usr/bin/env python3
"""`fetch_engine.py --matches <vendor>` accepts only a tree prepared for this checkout's exact lock.

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

    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print("fetch_engine --matches accepts only this checkout's lock")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
