#!/usr/bin/env python3
"""Keep Harmony snapshot preview on the native, complete-document validator.

Line-counting the downloaded NDJSON in ArkTS once shipped truncated snapshots as validated
previews: the Engine reader intentionally consumes only stageable records and does not authenticate
the cloud envelope. This check keeps the host wired to the C ABI that verifies the footer, body
digest, record identities and full-file identity before preview or enqueue.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ACCOUNT = ROOT / "platforms/harmony/entry/src/main/ets/account/HarmonyAccountCloudBridge.ets"
NATIVE = ROOT / "platforms/harmony/native/client_napi.cpp"
TYPES = ROOT / "platforms/harmony/entry/src/main/cpp/types/libmsimeclient/index.d.ts"
HEADER = ROOT / "crates/host-api/include/msime_client.h"


def main() -> int:
    account = ACCOUNT.read_text(encoding="utf-8")
    native = NATIVE.read_text(encoding="utf-8")
    types = TYPES.read_text(encoding="utf-8")
    header = HEADER.read_text(encoding="utf-8")
    start = account.index("  private async downloadSnapshot(")
    download = account[start : account.index("\n  private enqueue(", start)]

    required = {
        "C ABI declaration": "msime_client_snapshot_inspect" in header,
        "NAPI call": "TEXT_ENTRY(SnapshotInspect, msime_client_snapshot_inspect)" in native,
        "NAPI export": 'ENTRY("snapshotInspect", SnapshotInspect)' in native,
        "ArkTS declaration": "export const snapshotInspect:" in types,
        "download inspection": "this.inspectSnapshot(this.snapshotFile)" in download,
        "UUID activation id": "util.generateRandomUUID(false)" in account
        and "activation_id: token" in account,
        "file identity replay guard": "inspected.fileSha256 !== this.snapshotMetadata.fileSha256"
        in account,
    }
    problems = [name for name, present in required.items() if not present]
    if "response.body.split(" in download:
        problems.append("ArkTS line parser removed")
    if problems:
        print(
            "harmony snapshot inspection: missing " + ", ".join(problems),
            file=sys.stderr,
        )
        return 1
    print("harmony snapshot inspection: native envelope and file-identity checks are wired")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
