"""Resolve the immutable MSIME-Windows source used by parity checks.

The migration compares against one reviewed object, not whatever the reference repository happens
to publish tomorrow.  The checkout location may vary between machines; the object may not.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

PINNED_SHA = "345cb87a3822f6ad7013bb29506fe3d856c1931a"
PINNED_REF = "fixed source"


def reference_root(repository_root: pathlib.Path) -> pathlib.Path:
    """Find the sibling reference checkout from either a main or linked worktree."""
    override = os.environ.get("MSIME_REFERENCE_DIR")
    if override:
        return pathlib.Path(override)
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=repository_root,
        capture_output=True,
        text=True,
    )
    if common.returncode == 0 and common.stdout.strip():
        main = pathlib.Path(common.stdout.strip()).parent
        return main.parent / "MSIME-Windows"
    return repository_root.parent / "MSIME-Windows"


def pinned_reference(repository_root: pathlib.Path) -> tuple[pathlib.Path, str, str] | None:
    """Return (checkout, display ref, SHA), or None only when no checkout is available.

    A present checkout that lacks the pinned object is an invalid verification environment, not an
    excuse to fall back to a mutable branch.  Name the exact recovery command without running it:
    fetching changes the adjacent repository and may require network access.
    """
    checkout = reference_root(repository_root)
    if not (checkout / ".git").exists():
        return None
    present = subprocess.run(
        ["git", "cat-file", "-e", f"{PINNED_SHA}^{{commit}}"],
        cwd=checkout,
        capture_output=True,
        text=True,
    )
    if present.returncode != 0:
        print(
            f"FAIL {checkout} does not contain the fixed MSIME-Windows source {PINNED_SHA}",
            file=sys.stderr,
        )
        print("  fetch that exact commit into the reference checkout, then retry", file=sys.stderr)
        raise SystemExit(1)
    return checkout, PINNED_REF, PINNED_SHA


def show_file(repository_root: pathlib.Path, path: str) -> tuple[str, str, str] | None:
    """Read one file from the fixed source without checking out or moving any reference branch."""
    resolved = pinned_reference(repository_root)
    if resolved is None:
        return None
    checkout, ref, sha = resolved
    shown = subprocess.run(
        ["git", "show", f"{sha}:{path}"],
        cwd=checkout,
        capture_output=True,
        text=True,
    )
    if shown.returncode != 0:
        print(f"FAIL fixed MSIME-Windows source does not contain {path}", file=sys.stderr)
        raise SystemExit(1)
    return shown.stdout, ref, sha
