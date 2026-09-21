#!/usr/bin/env python3
"""Add the sixth helpcode scheme, 加加 (jiajia), to the locked Engine.

The reference ships six helpcode tables; the Engine archive this repository locks carries five. The
sixth was added to the reference *after* `metasequoiaime/MSIME-Engine` stopped taking commits - that
repository's HEAD is the very commit `engine-lock.json` pins, because the Engine moved in-repo to
the reference - so there is no newer Engine to bump the lock to. The table therefore travels with
this repository, in `resources/helpcodes/`, and is injected here.

Registration is a single entry in the Engine's own asset contract. `HelpcodeUtils` resolves a scheme
by searching `metasequoia::assets::helpcodes`, and `is_supported_helpcode_schema` searches the same
array, so one entry makes the scheme both loadable and valid. `contracts/assets/generate.py` turns
the contract into that array, and `product.py` derives the packaging file list from it, so running
the Engine's own generator is what keeps the three in agreement - rather than hand-editing the
generated header and hoping.

The table's provenance and its distribution restrictions are in `resources/helpcodes/NOTICE.md`.
Removing this script from `engine-lock.json` removes the scheme from the product entirely.
"""

import json
import subprocess
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
TABLE = REPOSITORY / "resources/helpcodes/jiajia_helpcode.txt"

# What the reference's asset contract says about this table, entry for entry.
ASSET = {
    "id": "helpcode_jiajia",
    "path": "helpcodes/jiajia_helpcode.txt",
    "role": "resource",
    "source": "helpcode/helpcodes/jiajia_helpcode.txt",
    "profiles": ["desktop"],
    "schema": "jiajia",
}


def apply(root: Path) -> None:
    if not TABLE.is_file():
        raise RuntimeError(f"Helpcode table is missing: {TABLE}")

    contract_path = root / "contracts/assets/assets.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    assets = contract["assets"]
    if any(entry.get("schema") == ASSET["schema"] for entry in assets):
        # A future Engine that carries the scheme itself. Leave all of it alone - its own table is
        # the one to use, and this overlay has nothing left to add.
        return

    table = root / ASSET["source"]
    if not table.parent.is_dir():
        raise RuntimeError(f"Engine overlay did not match: {table.parent} is not a directory")
    table.write_bytes(TABLE.read_bytes())

    # After the other helpcodes, which is where the reference puts it - the generated array is
    # ordered, and the settings page lists the schemes in the order the Engine reports them.
    last_helpcode = max(
        index for index, entry in enumerate(assets) if entry.get("id", "").startswith("helpcode_")
    )
    assets.insert(last_helpcode + 1, ASSET)
    contract_path.write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    # The Engine's own generator, so the header, the schema validation and the packaging list are
    # regenerated from one edited contract instead of being patched separately.
    generator = root / "contracts/assets/generate.py"
    result = subprocess.run(
        [sys.executable, str(generator)], cwd=generator.parent, capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"Engine asset generator failed: {result.stderr.strip()}")

    header = (root / "contracts/assets/assets.h").read_text(encoding="utf-8")
    if '{"jiajia", helpcode_jiajia}' not in header:
        raise RuntimeError("Engine asset header did not pick up the jiajia scheme")
