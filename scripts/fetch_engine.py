#!/usr/bin/env python3
"""Prepare the locked Engine tree the native build compiles against.

The Engine and its third-party sources are fetched as verified source archives. The lock records a
commit and SHA-256 for every archive, so this repository never needs a ``.gitmodules`` file or a
recursive Git checkout in order to build. The operation is idempotent: a prepared tree carrying the
same lock marker is left alone.

A SHA-256 over a GitHub-generated tarball is also a hash of the repository's *name*. The archive
GitHub builds for a commit puts every file under ``<current-repo-name>-<sha>/``, so renaming the
repository changes those bytes while changing nothing about the content. That happened on
2026-09-21: ``MSIME-Engine`` became ``msime-engine``, the Engine archive started hashing to
``40df62bf…`` where the lock said ``829a6cf1…``, no cold checkout could prepare the Engine, and the
four dependency archives in the same lock kept verifying — which is what pointed at this one
repository rather than at GitHub's tarball machinery.

The lock was re-pinned only after the content was checked against the commit itself, and that order
is the point. Re-pinning to whatever is served today would be the lock agreeing with the thing it
exists to check; a rename is indistinguishable from a substitution until you look. What was done:
clone the repository, resolve ``f611f2ff…``, and compare the archive's files against that commit's
blobs by hash. 462 of 462 matched, and the only entries in the commit without a file in the archive
were the four submodule gitlinks, which GitHub's tarballs never carry and which this lock fetches
separately as ``dependencies``. Anyone re-pinning this again should reproduce that comparison rather
than trust a digest that is merely stable across two downloads — stability only says the server is
consistent, not that it is serving what the commit says.
"""
import hashlib
import json
import runpy
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


def lock_marker(lock: dict) -> str:
    """Include deterministic local compatibility overlays in the prepared marker.

    By content, not by name. An overlay names a rewrite of the Engine's source, so editing one is
    editing the Engine - but a marker listing only file names is equal before and after that edit,
    the prepared tree is left alone, and the change silently does not apply. Measured on
    2026-09-21 while adding the English-display overlay: the tree kept the old rule and the test
    that should have failed passed.
    """
    scripts = {}
    for name in lock.get("overlay_scripts", []) + lock.get("overlay_assets", []):
        path = ROOT / name
        digest = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "missing"
        scripts[name] = digest
    overlays = json.dumps(
        {"patches": lock.get("patches", []), "scripts": scripts},
        sort_keys=True,
        separators=(",", ":"),
    )
    return f"{lock['commit']}\n{overlays}"


def prepared_at_lock(lock: dict) -> bool:
    """Whether DEST contains every source tree named by the lock and no Git metadata."""
    if not MARKER.is_file() or MARKER.read_text() != lock_marker(lock):
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


def apply_patches(directory: Path, lock: dict) -> None:
    """Apply small, reviewed compatibility fixes absent from the locked archive."""
    for patch in lock.get("patches", []):
        target = directory / patch["path"]
        if not target.is_file():
            raise RuntimeError(f"Engine overlay target is missing: {patch['path']}")
        contents = target.read_text()
        before = patch["find"]
        after = patch["replace"]
        if before in contents:
            target.write_text(contents.replace(before, after, 1))
        elif after not in contents:
            raise RuntimeError(f"Engine overlay did not match: {patch['path']}")


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
        apply_patches(staging, lock)
        for overlay in lock.get("overlay_scripts", []):
            script = ROOT / overlay
            if not script.is_file():
                raise RuntimeError(f"Engine overlay script is missing: {overlay}")
            namespace = runpy.run_path(str(script), run_name="__engine_overlay__")
            apply_overlay = namespace.get("apply")
            if not callable(apply_overlay):
                raise RuntimeError(f"Engine overlay has no apply() function: {overlay}")
            apply_overlay(staging)
        remove_git_metadata(staging)
        if DEST.exists():
            shutil.rmtree(DEST)
        DEST.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(DEST))
    MARKER.write_text(lock_marker(lock))
    print(f"Prepared Engine {lock['commit']} at {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
