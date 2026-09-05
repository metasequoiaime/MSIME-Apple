#!/usr/bin/env python3
"""Fetch the dictionary the product lock names and verify it against the committed digests.

This used to be built here, by platforms/macos/scripts/build_dictionary.py, which ran two of the four MSIME-Dict stages that write into msime.db. The bundle therefore shipped a database without the quick-phrase and Japanese lexicon tables that MSIME-Windows and MSIME-Linux ship, from a submodule pin that was five commits behind the released tag, with no digest to catch either. Nothing reported it, because a smaller database is still a valid one.

MSIME-Engine publishes msime.db and SHA256SUMS.txt as release assets and both other platforms already take them from there, so take them here too. That is what makes the claim in MSIME-Linux/scripts/fetch_dictionary.py true: all three platforms ship a byte-identical msime.db.

The release tag cannot be overridden from the command line. product-lock.json names it and records the SHA256 of every asset, so a retagged release or a replaced database fails the build instead of shipping: rewriting the upstream SHA256SUMS.txt along with the data does not help, because that file is verified against a committed digest too. Move to a new release with `python3 scripts/product_lock.py refresh --dictionary-tag dict-YYYY.MM.DD` and review the resulting diff.

    python3 scripts/fetch_dictionary.py
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import product_lock

ROOT = Path(__file__).resolve().parents[1]

# Unchanged from when the database was built here, so the METASEQUOIA_IME_DICTIONARY default in
# CMakeLists.txt keeps working without edits.
OUTPUT_DIR = ROOT / "vendor" / "MetasequoiaImeDict" / "out"


def verify_contents(destination: Path) -> None:
    """The digests prove we got what was reviewed; these probes prove it is usable.

    The quick-phrase probe is the one that would have caught the old build: quick_parases is written by a stage platforms/macos/scripts/build_dictionary.py never ran.
    """
    main_db = destination / "msime.db"

    with sqlite3.connect(main_db) as database:
        integrity = database.execute("PRAGMA integrity_check").fetchone()
        candidate = database.execute(
            "SELECT value FROM tbl_2_n WHERE key = ? ORDER BY weight DESC LIMIT 1", ("ni'hao",)
        ).fetchone()
        quick_phrase = database.execute(
            "SELECT value FROM quick_parases WHERE key = ? ORDER BY weight DESC,value LIMIT 1", ("yyds",)
        ).fetchone()
        wubi_candidate = database.execute(
            "SELECT value FROM wubi86 WHERE key = ? ORDER BY weight DESC LIMIT 1", ("aaaa",)
        ).fetchone()

    if (
        integrity != ("ok",)
        or candidate is None
        or quick_phrase != ("永远滴神",)
        or wubi_candidate is None
    ):
        raise SystemExit("Downloaded dictionary failed integrity or candidate verification.")

    print(
        f"{main_db.name} ({main_db.stat().st_size} bytes), "
        f"ni'hao -> {candidate[0]}, yyds -> {quick_phrase[0]}, aaaa -> {wubi_candidate[0]}"
    )


def main() -> None:
    data = product_lock.load()
    tag = data["dictionary"]["tag"]
    print(f"Fetching {tag} from {data['dictionary']['repository']}")

    # Everything is verified in a staging directory first. A failed or tampered download then leaves a previous usable checkout untouched instead of half replacing it. The staging directory sits inside the output directory because vendor/MetasequoiaImeDict is gitignored and on the same filesystem, so it neither dirties the checkout around it nor copies across devices.
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    assets = data["dictionary"]["assets"]
    with tempfile.TemporaryDirectory(dir=OUTPUT_DIR) as temporary:
        incoming = Path(temporary)
        product_lock.download_assets(tag, incoming, data["dictionary"]["repository"])
        product_lock.verify_assets(incoming, data)
        # Not an f-string expression: nesting the same quote character inside one needs Python 3.12, and this script has to run under the interpreter a stock macOS ships.
        print(f"verified {len(assets)} assets against product-lock.json")
        verify_contents(incoming)
        # Published through a rename so an interrupted publish cannot leave a truncated database that CMake, which only checks that the path exists, would happily bundle.
        for name in assets:
            staged = OUTPUT_DIR / f".{name}.incoming"
            shutil.copyfile(incoming / name, staged)
            staged.replace(OUTPUT_DIR / name)
    # The lock names the whole product, so anything else here is left over from a different lock and would otherwise be bundled beside a dictionary it does not describe.
    for stale in OUTPUT_DIR.iterdir():
        if stale.is_file() and stale.name not in assets:
            stale.unlink()
    print(f"staged into {OUTPUT_DIR}")


if __name__ == "__main__":
    sys.exit(main())
