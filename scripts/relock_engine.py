#!/usr/bin/env python3
"""Rewrite engine-lock.json for a given MSIME-Engine commit, including every submodule it pins."""
import hashlib, json, os, re, subprocess, sys, tarfile, tempfile, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "engine-lock.json"
ENGINE = "metasequoiaime/MSIME-Engine"


def archive_url(repository, commit):
    return f"https://github.com/{repository}/archive/{commit}.tar.gz"


def download(url, destination):
    urllib.request.urlretrieve(url, destination)
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def api(path):
    request = urllib.request.Request(f"https://api.github.com/{path}", headers={"Accept": "application/vnd.github+json"})
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def submodules(gitmodules):
    """Read .gitmodules as (path, repository) pairs. The tarball has no gitlinks, so the commits come from the API."""
    entries, current = [], {}
    for line in gitmodules.splitlines():
        line = line.strip()
        if line.startswith("[submodule"):
            current = {}
            entries.append(current)
        elif "=" in line and entries:
            key, _, value = line.partition("=")
            current[key.strip()] = value.strip()
    pairs = []
    for entry in entries:
        url = re.sub(r"\.git\Z", "", entry["url"])
        pairs.append((entry["path"], "/".join(url.split("/")[-2:])))
    return pairs


def main():
    commit = sys.argv[1] if len(sys.argv) > 1 else subprocess.run(
        ["git", "ls-remote", f"https://github.com/{ENGINE}.git", "refs/heads/main"],
        check=True, capture_output=True, text=True).stdout.split()[0]
    url = archive_url(ENGINE, commit)
    with tempfile.TemporaryDirectory() as td:
        archive = Path(td) / "engine.tar.gz"
        lock = {"repository": ENGINE, "commit": commit, "archive": url, "sha256": download(url, archive), "submodules": []}
        with tarfile.open(archive, "r:gz") as handle:
            root = handle.getnames()[0].split("/")[0]
            gitmodules = handle.extractfile(f"{root}/.gitmodules").read().decode()
        for path, repository in submodules(gitmodules):
            pinned = api(f"repos/{ENGINE}/contents/{path}?ref={commit}")["sha"]
            nested = Path(td) / path.replace("/", "_")
            entry_url = archive_url(repository, pinned)
            lock["submodules"].append({
                "path": path,
                "repository": repository,
                "commit": pinned,
                "archive": entry_url,
                "sha256": download(entry_url, nested),
            })
    LOCK.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"locked Engine {commit} with {len(lock['submodules'])} submodules")


if __name__ == "__main__":
    main()
