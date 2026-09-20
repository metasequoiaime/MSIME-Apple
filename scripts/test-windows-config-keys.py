#!/usr/bin/env python3
"""Every configuration key the reference ships has a counterpart here.

The Windows factory configuration is the most complete list of what the
reference product can be told to do: 180 keys across eighteen sections. A key it
has and this repository does not is a feature that was never migrated, and
nothing else notices - the settings page renders what it knows about, the
preferences struct parses what it declares, and neither has any idea the other
product offers more.

Finding the two `[statistics]` keys this way is what this check exists to repeat
without anybody remembering to do it by hand.

The comparison is on key names, not values: the two products deliberately differ
on some defaults, and those are checked by `test-default-config-parity.py`.
Keys this repository adds are fine and are not reported - the adaptation is
allowed to offer more, just not less.

The reference checkout is optional. Without it the check reports what it would
have needed and passes, the same as every other stage that depends on something
not every machine has.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OURS = ROOT / "platforms/windows/installer/config.default.toml"
REFERENCE_CONFIG = "installer/default_config/config.default.toml"


def reference_root() -> pathlib.Path:
    """Where the reference checkout is.

    Beside the *main* worktree, not beside this one: development here happens in short-lived
    worktrees under `~/worktrees`, so resolving against the current checkout would make this
    check skip forever and look like it was passing. `MSIME_REFERENCE_DIR` overrides it.
    """
    override = os.environ.get("MSIME_REFERENCE_DIR")
    if override:
        return pathlib.Path(override)
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if common.returncode == 0 and common.stdout.strip():
        # <main worktree>/.git -> <main worktree> -> its parent holds the sibling checkouts.
        main = pathlib.Path(common.stdout.strip()).parent
        return main.parent / "MSIME-Windows"
    return ROOT.parent / "MSIME-Windows"


REFERENCE = reference_root()

# Keys the reference has that this repository answers somewhere other than a configuration key of
# the same name. Each needs the reason, because "it is handled elsewhere" is exactly what someone
# would write to make this check quiet.
ANSWERED_ELSEWHERE: dict[str, str] = {}


def keys(text: str) -> set[str]:
    section = None
    found: set[str] = set()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", stripped)
        if match:
            found.add(f"{section}.{match.group(1)}")
    return found


def reference_revision() -> tuple[str, str] | None:
    """(ref, sha) of the reference's default branch, or None.

    Not the local `origin/HEAD`: that symbolic ref is written once at clone time and here it
    still points at `origin/main`, the release branch, which lags the default branch by thirty
    configuration keys. Comparing against it would report everything present while the reference
    had moved on - the exact false pass this check exists to prevent. The remote is asked what
    its default branch is, and the ref that was used is always printed so the answer is never
    anonymous.
    """
    if not (REFERENCE / ".git").exists():
        return None
    symref = subprocess.run(
        ["git", "ls-remote", "--symref", "origin", "HEAD"],
        cwd=REFERENCE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    candidates = []
    if symref.returncode == 0:
        match = re.search(r"^ref:\s+refs/heads/(\S+)\s+HEAD$", symref.stdout, re.M)
        if match:
            candidates.append(f"origin/{match.group(1)}")
    # Offline, or a remote that does not advertise one. `develop` is this reference's default
    # branch and the object the parity document pins; `origin/HEAD` is the last resort and is
    # named in the output so a stale one is visible.
    candidates += ["origin/develop", "origin/HEAD"]
    for ref in candidates:
        revision = subprocess.run(
            ["git", "rev-parse", ref], cwd=REFERENCE, capture_output=True, text=True
        )
        if revision.returncode == 0:
            return ref, revision.stdout.strip()
    return None


def reference_config() -> tuple[str, str, str] | None:
    resolved = reference_revision()
    if resolved is None:
        return None
    ref, sha = resolved
    shown = subprocess.run(
        ["git", "show", f"{sha}:{REFERENCE_CONFIG}"],
        cwd=REFERENCE,
        capture_output=True,
        text=True,
    )
    return (shown.stdout, ref, sha) if shown.returncode == 0 else None


def main() -> int:
    resolved = reference_config()
    if resolved is None:
        print("skipped: no MSIME-Windows checkout beside this repository to compare against")
        print(f"  expected a git checkout at {REFERENCE}")
        return 0
    text, ref, sha = resolved
    theirs = keys(text)
    ours = keys(OURS.read_text(encoding="utf-8"))
    missing = sorted(key for key in theirs - ours if key not in ANSWERED_ELSEWHERE)

    for key in missing:
        print(f"FAIL {key}: the reference configures this and nothing here does", file=sys.stderr)
    if missing:
        print(
            "\nEither migrate the feature, or record in ANSWERED_ELSEWHERE where this repository "
            "answers it and why the key does not exist.",
            file=sys.stderr,
        )
        return 1
    extra = len(ours - theirs)
    print(
        f"windows config keys: all {len(theirs)} keys of {ref} ({sha[:8]}) are present"
        + (f", plus {extra} this repository adds" if extra else "")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
