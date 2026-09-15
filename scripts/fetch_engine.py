#!/usr/bin/env python3
"""Download and verify the immutable Engine archive used by Apple builds."""
import hashlib, json, shutil, subprocess, sys, tarfile, tempfile, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "engine-lock.json"
DEST = ROOT / "vendor/MetasequoiaImeEngine"

def main():
    lock = json.loads(LOCK.read_text())
    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / "engine.tar.gz"
        urllib.request.urlretrieve(lock["archive"], archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != lock["sha256"]:
            raise SystemExit(f"Engine archive SHA256 mismatch: {digest}")
        with tarfile.open(archive, "r:gz") as handle:
            handle.extractall(td)
        extracted = next(Path(td).glob("MSIME-Engine-*"))
        if DEST.exists():
            shutil.rmtree(DEST)
        shutil.copytree(extracted, DEST)
    # GitHub source archives omit the Engine's own submodules. Restore those pinned entries so
    # Xcode and CMake see the same complete tree as a recursive checkout.
    subprocess.run(["git", "-C", str(DEST), "init", "-q"], check=True)
    subprocess.run(["git", "-C", str(DEST), "remote", "add", "origin", "https://github.com/metasequoiaime/MSIME-Engine.git"], check=False)
    subprocess.run(["git", "-C", str(DEST), "fetch", "-q", "--depth", "1", "origin", lock["commit"]], check=True)
    subprocess.run(["git", "-C", str(DEST), "checkout", "-q", "FETCH_HEAD"], check=True)
    subprocess.run(["git", "-C", str(DEST), "submodule", "update", "--init", "--recursive", "--depth", "1"], check=True)
    print(f"prepared Engine {lock['commit']} at {DEST}")

if __name__ == "__main__":
    main()
