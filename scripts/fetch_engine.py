#!/usr/bin/env python3
"""Prepare the locked Engine tree the native build compiles against.

The Engine and its third-party sources are fetched as verified source archives. The lock records a
commit and SHA-256 for every archive, so this repository never needs a ``.gitmodules`` file or a
recursive Git checkout in order to build. The operation is idempotent: a prepared tree carrying the
same lock marker is left alone.
"""
import hashlib
import json
import shutil
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "engine-lock.json"
DEST = ROOT / "vendor/MSIME-Engine"
MARKER = DEST / ".msime-engine-lock"


def prepared_at_lock(lock: dict) -> bool:
    """Whether DEST contains every source tree named by the lock and no Git metadata."""
    if not MARKER.is_file() or MARKER.read_text().strip() != lock["commit"]:
        return False
    if any(path.name in {".git", ".gitmodules"} for path in DEST.rglob("*") if path.is_dir()):
        return False
    if any(path.name == ".gitmodules" for path in DEST.rglob("*")):
        return False
    return all((DEST / dependency["path"]).is_dir() for dependency in lock["dependencies"])


def download_and_extract(artifact: dict, directory: Path) -> Path:
    """Download, verify, and extract one GitHub source archive."""
    archive = directory / "source.tar.gz"
    directory.mkdir(parents=True)
    urllib.request.urlretrieve(artifact["archive"], archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != artifact["sha256"]:
        raise RuntimeError(
            f"archive SHA-256 mismatch for {artifact['repository']}: "
            f"expected {artifact['sha256']}, got {digest}"
        )
    extracted = directory / "extracted"
    extracted.mkdir()
    with tarfile.open(archive, "r:gz") as source:
        members = source.getmembers()
        for member in members:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"unsafe archive member: {member.name}")
        source.extractall(extracted)
    roots = {member.name.split("/", 1)[0] for member in members if member.name}
    if len(roots) != 1:
        raise RuntimeError(f"archive for {artifact['repository']} has no single root directory")
    return extracted / roots.pop()


def remove_git_metadata(directory: Path) -> None:
    """Keep fetched source trees independent of Git and submodule metadata."""
    for path in sorted(directory.rglob(".gitmodules"), reverse=True):
        path.unlink()
    for path in sorted((path for path in directory.rglob(".git") if path.is_dir()), reverse=True):
        shutil.rmtree(path)


def main() -> int:
    lock = json.loads(LOCK.read_text())
    if prepared_at_lock(lock):
        print(f"Engine already prepared at {lock['commit']}")
        return 0
    with tempfile.TemporaryDirectory() as directory:
        staging = Path(directory) / "staging"
        staging.mkdir()
        engine = download_and_extract(lock, Path(directory) / "engine")
        shutil.copytree(engine, staging, dirs_exist_ok=True)
        for dependency in lock["dependencies"]:
            dependency_root = download_and_extract(dependency, Path(directory) / dependency["path"])
            destination = staging / dependency["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(dependency_root, destination, dirs_exist_ok=True)
        remove_git_metadata(staging)
        if DEST.exists():
            shutil.rmtree(DEST)
        DEST.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(DEST))
    MARKER.write_text(lock["commit"] + "\n")
    print(f"Prepared Engine {lock['commit']} at {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
