#!/usr/bin/env python3
"""No tracked symlink may point outside the repository.

A symlink is one of the few things git stores that is not the same on the next machine: it records
the target as text, and an absolute one names a path that only exists where it was created. Checked
out anywhere else it is a dangling entry - and a dangling entry is worse than a missing one, because
the tools that would have created the real thing find something already there and stop.

This is not hypothetical. `vendor` was committed as `vendor -> /Users/<someone>/.../msime/vendor`,
an absolute path pointing at itself. Every fresh clone and every new worktree got it, and
`scripts/fetch_engine.py` then failed on `mkdir(exist_ok=True)` - which does not forgive a path that
exists but is not a directory - so the Engine could not be prepared at all. The failure named
`FileExistsError` on a directory the checkout was supposed to create itself, which points nowhere
near a symlink someone committed by accident.

Relative links that stay inside the tree are fine and are what a repository should contain; they
mean the same thing wherever they are checked out.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def tracked_symlinks() -> list[tuple[str, str]]:
    """(path, target) for every symlink in the index, read from git rather than from disk.

    From the index: on a checkout where one of these is already dangling, walking the working tree
    would still find it, but reading the recorded target is what this is actually about.
    """
    listing = subprocess.run(
        ["git", "ls-files", "-s"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    found = []
    for line in listing.stdout.splitlines():
        if not line.startswith("120000 "):
            continue
        blob = line.split()[1]
        path = line.split("\t", 1)[1]
        target = subprocess.run(
            ["git", "cat-file", "-p", blob], cwd=ROOT, capture_output=True, text=True, check=True
        )
        found.append((path, target.stdout.strip()))
    return found


def escapes(path: str, target: str) -> bool:
    if os.path.isabs(target):
        return True
    # Resolve the link the way the filesystem would - from the directory holding it - and ask
    # whether the result is still under the repository root. `..` is allowed as long as it lands
    # back inside.
    resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
    return resolved == ".." or resolved.startswith("../")


def main() -> int:
    offenders = [(path, target) for path, target in tracked_symlinks() if escapes(path, target)]
    for path, target in offenders:
        kind = "an absolute path" if os.path.isabs(target) else "outside the repository"
        print(f"FAIL {path} -> {target}: {kind}, so it means nothing on another checkout", file=sys.stderr)
    if offenders:
        print(
            "\nCommit the file itself, or let the checkout create the link - a tracked symlink has "
            "to resolve inside the repository to survive being cloned.",
            file=sys.stderr,
        )
        return 1
    total = len(tracked_symlinks())
    print(
        f"tracked symlinks: {total} tracked, all resolving inside the repository"
        if total
        else "tracked symlinks: none"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
