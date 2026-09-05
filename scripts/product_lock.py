#!/usr/bin/env python3
"""Maintain and consume the reviewed Apple product dependency lock.

This mirrors MSIME-Linux/scripts/product_lock.py deliberately, so the two can be diffed. The only intended difference is the asset set: the macOS bundle installs msime.db and nothing else, so others.db and english.db are not locked here. Add them here and to CMakeLists.txt together if the bundle ever ships them.

Engine, helpcodes and the mobile builder share one Engine gitlink. Git already makes those immutable and shows every move in a pull request diff, so they are not copied into this lock: doing that would only give the submodule pin a second home to drift from.

The dictionary the bundle actually *ships* is the one input git does not pin. It is a release asset behind a tag that upstream can retag, and the SHA256SUMS.txt published beside it is exactly as mutable as the data. So product-lock.json holds the tag and the SHA256 of every asset, and the build verifies those committed digests instead.

The dictionary's *source* commit is locked alongside the digests rather than read from a gitlink. MSIME-Linux learned that the hard way: its dict gitlink recorded 55bd649 while every shipped byte came from 0c7368c, because nothing moves that pin in lockstep with the release tag (MSIME-Linux#47). The commit the tag resolves to is the only one that produced the data, so `refresh` resolves it at the moment the data is reviewed. The Engine gitlink also owns the mobile-profile builder, never the source identity of the released database.

`refresh` is the only command that reaches upstream. `manifest` records what a build consumed: the source commit, every gitlink, the locked dictionary and the digest of the lock itself.
"""

from __future__ import annotations

import argparse
import importlib.util
import hashlib
import json
import re
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_product_spec = importlib.util.spec_from_file_location("dictionary_product", Path(__file__).with_name("dictionary_product.py"))
_product = importlib.util.module_from_spec(_product_spec)
_product_spec.loader.exec_module(_product)
PRODUCT_MANIFEST = _product.MANIFEST_NAME
LEGACY_DICTIONARY_TAG = "dict-2026.09.05"


REPOSITORY = "metasequoiaime/MSIME-Apple"
DICTIONARY_REPOSITORY = "metasequoiaime/MSIME-Engine"
DICTIONARY_URL = f"https://github.com/{DICTIONARY_REPOSITORY}.git"

# Every gitlink this repository builds from. The manifest reads their commits here rather than from
# a second copy in the lock, so there is one source of truth for what was checked out.
SUBMODULES = {
    "engine": ("metasequoiaime/MSIME-Engine", "vendor/MetasequoiaImeEngine"),
}

# The database CMakeLists.txt installs into the bundle, plus the checksum file the release publishes
# beside it. The checksum file is locked too so a rewritten one is caught rather than trusted.
DATABASES = ("msime.db",)
ASSETS = (*DATABASES, "SHA256SUMS.txt")

SHA = re.compile(r"[0-9a-f]{40}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
TAG = re.compile(r"dict-[A-Za-z0-9._-]+\Z")


def validate(data: dict) -> dict:
    if data.get("schema_version") != 1:
        raise ValueError("Unsupported product lock schema_version")
    dictionary = data.get("dictionary", {})
    if dictionary.get("repository") != DICTIONARY_REPOSITORY and not (
        dictionary.get("repository") == "metasequoiaime/MSIME-Dict" and dictionary.get("tag") == LEGACY_DICTIONARY_TAG
    ):
        raise ValueError("Unexpected dictionary repository")
    if not TAG.fullmatch(dictionary.get("tag", "")):
        raise ValueError("Dictionary tag must be an explicit dict-* release, never latest")
    if not SHA.fullmatch(dictionary.get("source_commit", "")):
        raise ValueError("Dictionary source_commit must be the full commit the release tag resolves to")
    assets = dictionary.get("assets", {})
    expected_assets = set(ASSETS) if dictionary['tag'] == LEGACY_DICTIONARY_TAG else set(ASSETS) | {PRODUCT_MANIFEST}
    if set(assets) != expected_assets:
        raise ValueError("Dictionary lock must cover every shipped database and the checksum file")
    for name, digest in assets.items():
        if not DIGEST.fullmatch(digest):
            raise ValueError(f"Invalid SHA256 for {name}")
    return data


def load(path: Path = ROOT / "product-lock.json") -> dict:
    return validate(json.loads(path.read_text(encoding="utf-8")))


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_assets(directory: Path, data: dict) -> None:
    """Fail on the committed digest, never on the checksum file that shipped with the data."""
    for name, expected in data["dictionary"]["assets"].items():
        path = directory / name
        if not path.is_file():
            raise ValueError(f"Locked dictionary asset is missing: {name}")
        actual = sha256(path)
        if actual != expected:
            raise ValueError(f"{name} does not match the product lock: expected {expected}, got {actual}")

    if PRODUCT_MANIFEST in data["dictionary"]["assets"]:
        manifest = _product.verify_product(directory, "desktop", DATABASES)
        source = manifest.get("source", {})
        if (source.get("repository") != data["dictionary"]["repository"] or
                source.get("commit") != data["dictionary"]["source_commit"] or source.get("dirty") is not False):
            raise ValueError("Dictionary manifest provenance does not match the reviewed source commit")


def download_assets(tag: str, destination: Path, repository: str = DICTIONARY_REPOSITORY) -> None:
    """Plain HTTPS rather than the GitHub CLI or the API.

    The release assets of a public repository are served unauthenticated from a CDN, so this needs no credentials and stays off the API and its rate limits.
    """
    if not TAG.fullmatch(tag):
        raise ValueError("Refusing to download from a tag that is not an explicit dict-* release")
    if repository not in (DICTIONARY_REPOSITORY, "metasequoiaime/MSIME-Dict"):
        raise ValueError("Unexpected dictionary repository")
    destination.mkdir(parents=True, exist_ok=True)
    names = ASSETS if tag == LEGACY_DICTIONARY_TAG else (*ASSETS, PRODUCT_MANIFEST)
    for name in names:
        url = f"https://github.com/{repository}/releases/download/{tag}/{name}"
        target = destination / name
        last_error: Exception | None = None
        for attempt in range(1, 4):
            try:
                with urllib.request.urlopen(url, timeout=120) as response, target.open("wb") as out:
                    while chunk := response.read(1 << 20):
                        out.write(chunk)
                break
            except (urllib.error.URLError, TimeoutError, OSError) as error:
                last_error = error
                print(f"  attempt {attempt} for {name} failed: {error}")
        else:
            raise ValueError(f"Could not download {url}: {last_error}")
        print(f"downloaded {name} ({target.stat().st_size} bytes)")


def resolve_tag_commit(tag: str) -> str:
    """Resolve a dict-* tag to the commit that built it, over the plain git protocol.

    Not the API: refresh runs wherever download_assets does, and ls-remote needs no credentials and no gh.

    Both refs are requested by name. ls-remote filters on the ref as written, and the peeled ref is literally named refs/tags/<tag>^{}, so asking only for refs/tags/<tag> gets an annotated tag's tag object and nothing else. A trailing glob would return the peeled ref too, but it would also match dict-2026.01.01-rc1.
    """
    if not TAG.fullmatch(tag):
        raise ValueError("Refusing to resolve a tag that is not an explicit dict-* release")
    output = subprocess.check_output(
        ["git", "ls-remote", DICTIONARY_URL, f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"], text=True
    )
    references = {}
    for line in output.splitlines():
        commit, _, reference = line.partition("\t")
        references[reference.strip()] = commit.strip()
    # An annotated tag lists the tag object under the plain name and the commit it points at under
    # ^{}; a lightweight one only has the plain reference. Locking the tag object's own SHA would
    # record something that is not a commit in MSIME-Dict's history at all, and it is 40 hex digits
    # like any other object, so nothing downstream would notice.
    commit = references.get(f"refs/tags/{tag}^{{}}") or references.get(f"refs/tags/{tag}")
    if not commit or not SHA.fullmatch(commit):
        raise ValueError(f"{tag} does not resolve to a commit in {DICTIONARY_REPOSITORY}")
    return commit


def published_checksums(directory: Path) -> dict[str, str]:
    checksums = {}
    for line in (directory / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        digest, _, name = line.partition("  ")
        if name.strip():
            checksums[name.strip()] = digest.strip()
    return checksums


def git(directory: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(directory), *args], text=True).strip()


def gitlinks(directory: Path) -> dict:
    submodules = {}
    for name, (repository, path) in SUBMODULES.items():
        fields = git(directory, "ls-tree", "HEAD", path).split()
        if len(fields) != 4 or fields[0] != "160000" or not SHA.fullmatch(fields[2]):
            raise ValueError(f"{path} is not a gitlink at an immutable commit in HEAD")
        submodules[name] = {"repository": repository, "path": path, "commit": fields[2]}
    return submodules


def manifest(directory: Path, commit: str, lock: Path, data: dict) -> dict:
    if not SHA.fullmatch(commit):
        raise ValueError("The source commit must be a full immutable SHA")
    return {
        "schema_version": 1,
        "source": {"repository": REPOSITORY, "commit": commit},
        "submodules": gitlinks(directory),
        "dictionary": data["dictionary"],
        "lock_sha256": sha256(lock),
    }


def refresh(tag: str) -> dict:
    """Resolve the digests of a dictionary release so a human can review the diff before it ships.

    Trusting the published SHA256SUMS.txt is appropriate here and only here: this is the one moment the data is looked at deliberately, and the digests it produces are what every later build is held to.
    """
    if not TAG.fullmatch(tag):
        raise ValueError("refresh requires an explicit dict-* release tag")
    with tempfile.TemporaryDirectory() as temporary:
        incoming = Path(temporary)
        download_assets(tag, incoming)
        published = published_checksums(incoming)
        assets = {}
        for name in (ASSETS if tag == LEGACY_DICTIONARY_TAG else (*ASSETS, PRODUCT_MANIFEST)):
            digest = sha256(incoming / name)
            if name in published and published[name] != digest:
                raise ValueError(f"{name} does not match the checksums published with {tag}")
            assets[name] = digest
        for name in DATABASES:
            if name not in published:
                raise ValueError(f"{name} has no entry in the SHA256SUMS.txt published with {tag}")
    source_commit = resolve_tag_commit(tag)
    print(f"locked {len(assets)} assets from {DICTIONARY_REPOSITORY} at {tag} ({source_commit})")
    return validate({
        "schema_version": 1,
        "dictionary": {
            "repository": DICTIONARY_REPOSITORY,
            "tag": tag,
            "source_commit": source_commit,
            "assets": assets,
        },
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lock", type=Path, default=ROOT / "product-lock.json")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    commands.add_parser("tag")
    verify = commands.add_parser("verify-dictionaries")
    verify.add_argument("directory", type=Path)
    record = commands.add_parser("manifest")
    record.add_argument("--source-commit", required=True)
    record.add_argument("--repository", type=Path, default=ROOT)
    record.add_argument("--output", type=Path, required=True)
    update = commands.add_parser("refresh")
    update.add_argument("--dictionary-tag", required=True)
    args = parser.parse_args()

    if args.command == "refresh":
        write_json(args.lock, refresh(args.dictionary_tag))
        return

    data = load(args.lock)
    if args.command == "tag":
        print(data["dictionary"]["tag"])
    elif args.command == "verify-dictionaries":
        verify_assets(args.directory, data)
    elif args.command == "manifest":
        write_json(args.output, manifest(args.repository, args.source_commit, args.lock, data))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
