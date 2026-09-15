#!/usr/bin/env python3
"""Prepare the locked Engine tree the native build compiles against.

The Engine used to be a git submodule. A submodule pins a commit but says nothing about what that
commit contains: whoever clones gets whatever the remote serves under that hash today, and a build
that forgot --recursive gets an empty directory and a compiler error a hundred lines later. The lock
here names the commit and the SHA-256 of its source archive, so the tree is verified before anything
is built from it, and a mirror that served something else would be caught rather than compiled.

The archive is verified and then the same commit is cloned: GitHub's source archives omit the
Engine's own submodules, which it needs, and there is no checksum to be had for those. Verifying the
archive still establishes that the commit the clone checks out is the one the lock describes.

Idempotent. A tree already at the locked commit, with its submodules in place, is left alone, so
this costs nothing on an incremental build.
"""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "engine-lock.json"
DEST = ROOT / "vendor/MSIME-Engine"


def at_locked_commit(commit: str) -> bool:
    """Whether DEST is already the locked commit with a populated submodule tree."""
    if not (DEST / ".git").exists():
        return False
    try:
        head = subprocess.run(["git", "-C", str(DEST), "rev-parse", "HEAD"],
                              check=True, capture_output=True, text=True).stdout.strip()
    except subprocess.CalledProcessError:
        return False
    if head != commit:
        return False
    # A submodule line beginning with '-' is one that was never checked out, which is exactly the
    # half-prepared tree this script exists to stop the compiler from meeting.
    status = subprocess.run(["git", "-C", str(DEST), "submodule", "status", "--recursive"],
                            check=True, capture_output=True, text=True).stdout
    return not any(line.startswith("-") for line in status.splitlines())


def main() -> int:
    lock = json.loads(LOCK.read_text())
    commit = lock["commit"]
    if at_locked_commit(commit):
        print(f"Engine already at {commit}")
        return 0
    with tempfile.TemporaryDirectory() as directory:
        archive = Path(directory) / "engine.tar.gz"
        urllib.request.urlretrieve(lock["archive"], archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != lock["sha256"]:
            print(f"Engine archive SHA-256 mismatch: expected {lock['sha256']}, got {digest}",
                  file=sys.stderr)
            return 1
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/{lock['repository']}.git"
    subprocess.run(["git", "clone", "-q", url, str(DEST)], check=True)
    subprocess.run(["git", "-C", str(DEST), "checkout", "-q", commit], check=True)
    subprocess.run(["git", "-C", str(DEST), "submodule", "update", "--init", "--recursive",
                    "--depth", "1"], check=True)
    print(f"Prepared Engine {commit} at {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
