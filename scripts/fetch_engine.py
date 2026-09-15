#!/usr/bin/env python3
"""Download and verify the immutable Engine archive used by Apple builds."""
import hashlib, json, shutil, tarfile, tempfile, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "engine-lock.json"
DEST = ROOT / "vendor/MetasequoiaImeEngine"
# Records which lock produced the tree that is already on disk. CMake runs this script on every configure, and without it a no-op configure spends minutes re-downloading and re-copying 130 MB.
STAMP = DEST / ".engine-lock.sha256"


def fetch(entry, destination):
    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / "source.tar.gz"
        urllib.request.urlretrieve(entry["archive"], archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise SystemExit(f"{entry['repository']} archive SHA256 mismatch: expected {entry['sha256']}, got {digest}")
        with tarfile.open(archive, "r:gz") as handle:
            handle.extractall(td)
        # A GitHub source archive holds exactly one top-level directory named <repo>-<commit>.
        extracted = next(path for path in Path(td).iterdir() if path.is_dir())
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(extracted, destination)


def main():
    text = LOCK.read_text()
    lock = json.loads(text)
    stamp = hashlib.sha256(text.encode()).hexdigest()
    if STAMP.exists() and STAMP.read_text().strip() == stamp:
        print(f"Engine {lock['commit']} already prepared at {DEST}")
        return
    fetch(lock, DEST)
    # GitHub source archives leave every submodule as an empty directory, so the Engine's own dependencies -- the pinyin tables, utfcpp, and the two voice libraries its CMake refuses to configure without -- have to be locked and unpacked the same way. Their commits are not recoverable from the Engine archive either: a tarball carries no gitlinks.
    for entry in lock.get("submodules", []):
        fetch(entry, DEST / entry["path"])
    STAMP.write_text(stamp + "\n")
    print(f"prepared Engine {lock['commit']} at {DEST}")


if __name__ == "__main__":
    main()
