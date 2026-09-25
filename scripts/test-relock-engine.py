#!/usr/bin/env python3
"""`relock_engine.py` changes only commit, archive and sha256, and refuses what is not an archive of the commit.

engine-update.yml once called this script before it existed, so every scheduled bump failed on a missing file. Offline: the download is replaced by an in-memory tarball.
"""

from __future__ import annotations

import hashlib
import io
import json
import pathlib
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import relock_engine  # noqa: E402


def tarball(*roots: str) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for root in roots:
            info = tarfile.TarInfo(f"{root}/README")
            info.size = 2
            archive.addfile(info, io.BytesIO(b"ok"))
    return buffer.getvalue()


def main() -> int:
    lock = json.loads((ROOT / "engine-lock.json").read_text(encoding="utf-8"))
    commit = "0123456789abcdef0123456789abcdef01234567"
    good = tarball(f"msime-engine-{commit}")
    requested = []
    failures = []

    def serve(data: bytes):
        def download(url: str) -> bytes:
            requested.append(url)
            return data
        return download

    updated = relock_engine.relock(lock, commit, serve(good))
    expected_url = f"https://github.com/{lock['repository']}/archive/{commit}.tar.gz"
    if requested != [expected_url]:
        failures.append(f"downloaded {requested}, not the lock repository's archive")
    if (updated["commit"], updated["archive"], updated["sha256"]) != (commit, expected_url, hashlib.sha256(good).hexdigest()):
        failures.append("commit, archive or sha256 not updated")
    if list(updated) != list(lock) or any(updated[key] != lock[key] for key in lock if key not in {"commit", "archive", "sha256"}):
        failures.append("fields other than commit, archive and sha256 changed")

    for bad in ["", "HEAD", commit[:39], commit.upper(), commit + "\nx"]:
        try:
            relock_engine.relock(lock, bad, serve(good))
            failures.append(f"accepted commit {bad!r}")
        except ValueError:
            pass
    for name, data in [("another commit", tarball("msime-engine-" + "f" * 40)), ("two roots", tarball(f"msime-engine-{commit}", "other"))]:
        try:
            relock_engine.relock(lock, commit, serve(data))
            failures.append(f"pinned an archive with {name}")
        except RuntimeError:
            pass

    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print("relock_engine changes only commit, archive and sha256")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
