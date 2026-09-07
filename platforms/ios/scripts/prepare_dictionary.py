#!/usr/bin/env python3
"""Package the locked, published databases without platform-side data transformations.

The locked upstream manifest authenticates supplemental databases, the Japanese
sentence model, and its required upstream attribution.
"""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "scripts"))
import product_lock
import product_lock_shared

FULL_DICTIONARY = REPOSITORY_ROOT / "vendor/MetasequoiaImeDict/out/msime.db"
IOS_DICTIONARY = REPOSITORY_ROOT / "platforms/ios/KeyboardExtension/Resources/msime.db"
DATABASES = ("msime.db", "english.db", "others.db")
ASSETS = (*DATABASES, "dict_japanese.dat", "mozc_dictionary_oss_README.txt")

def main():
    lock = product_lock.load()
    try:
        product_lock.verify_assets(FULL_DICTIONARY.parent, lock)
    except (OSError, ValueError):
        subprocess.run(["python3", "scripts/fetch_dictionary.py"], cwd=REPOSITORY_ROOT, check=True)
    product_lock.verify_assets(FULL_DICTIONARY.parent, lock)
    manifest = json.loads((FULL_DICTIONARY.parent / "dictionary-manifest.json").read_text())
    with tempfile.TemporaryDirectory() as temporary:
        staging = Path(temporary)
        for name in ASSETS:
            target = staging / name
            if name == "msime.db":
                shutil.copyfile(FULL_DICTIONARY, target)
            else:
                release = lock["dictionary"]
                url = f"https://github.com/{release['repository']}/releases/download/{release['tag']}/{name}"
                product_lock_shared.download_with_retries(url, target)
            digest = hashlib.sha256(target.read_bytes()).hexdigest()
            if digest != manifest["files"][name]["sha256"]:
                raise ValueError(f"{name}: digest differs from locked product manifest")
            (staging / (name + ".sha256")).write_text(digest + "\n")
        packaged = dict(manifest)
        packaged["profile"] = "ios-multischeme"
        packaged["files"] = {name: manifest["files"][name] for name in ASSETS}
        packaged["engine_compatibility"] = dict(manifest["engine_compatibility"], japanese_model_magic="MSJPDT1")
        packaged["japanese_sentence_model"] = True
        packaged["upstream_manifest_sha256"] = lock["dictionary"]["assets"]["dictionary-manifest.json"]
        (staging / "dictionary-manifest.json").write_text(json.dumps(packaged, indent=2) + "\n")
        IOS_DICTIONARY.parent.mkdir(parents=True, exist_ok=True)
        for path in staging.iterdir():
            shutil.copyfile(path, IOS_DICTIONARY.parent / path.name)
    print("Packaged verified pinyin, Wubi, Japanese lexicon, English and expressive databases")

if __name__ == "__main__":
    main()
