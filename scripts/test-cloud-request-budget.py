#!/usr/bin/env python3
"""Every host waits the same amount of time for a cloud candidate.

The budget belongs to the product, not to a host: the reference sets a 2000 ms connect and a 2500 ms
total on its own request, and a reply that arrives inside that is a candidate the user is meant to
see. Each host here reaches the network with its own library - NSURLSession on Apple, libcurl on
Windows - so nothing in the compiler stops one of them from quietly choosing a shorter deadline.
Two of them had: both asked for 2000 ms in total, which throws away exactly the replies that a slow
link produces, and does it invisibly, because a dropped cloud candidate looks the same as a query
that had no cloud answer.

So: the numbers are declared once in `client-core`, repeated in the C header the C++ and
Objective-C hosts read, and this checks that the declarations agree and that no host writes a
literal deadline of its own beside the call that uses them.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = ROOT / "crates/client-core/src/cloud/candidates.rs"
HEADER = ROOT / "crates/host-api/include/msime_client.h"
HOSTS = [
    (
        ROOT / "platforms/macos/src/cloud/CloudCandidateRequest.mm",
        ["MSIME_CLOUD_REQUEST_TIMEOUT_MS"],
        # Only the cloud-candidate initialiser. The translation and AI initialisers in the same
        # file set their own deadlines from the descriptors they validate a few lines earlier, so
        # a literal there is the host holding a contract rather than inventing one.
        (r"- \(instancetype\)initWithURL:", r"_timeout = ([0-9.]+)\s*;"),
    ),
    (
        ROOT / "platforms/windows/src/candidate/CloudCandidateWorker.cpp",
        ["MSIME_CLOUD_CONNECT_TIMEOUT_MS", "MSIME_CLOUD_REQUEST_TIMEOUT_MS"],
        (None, r"CURLOPT_\w*TIMEOUT\w*_MS,\s*([0-9]+)L"),
    ),
]
# What the reference asks for, so a change here is a change against it rather than a typo.
REFERENCE = {"CONNECT": 2000, "REQUEST": 2500}


def declared(path: pathlib.Path, pattern: str) -> dict[str, int]:
    text = path.read_text(encoding="utf-8")
    return {name: int(value) for name, value in re.findall(pattern, text)}


def main() -> int:
    if not SHARED.is_file() or not HEADER.is_file():
        print("skipped: the cloud candidate contract is not present")
        return 0
    failures: list[str] = []

    shared = declared(SHARED, r"pub const (CONNECT|REQUEST)_TIMEOUT_MS: u64 = (\d+)")
    header = declared(HEADER, r"#define MSIME_CLOUD_(CONNECT|REQUEST)_TIMEOUT_MS (\d+)")
    for name, expected in REFERENCE.items():
        if shared.get(name) != expected:
            failures.append(
                f"client-core's {name}_TIMEOUT_MS is {shared.get(name)}, and the reference asks for {expected}"
            )
        if header.get(name) != expected:
            failures.append(
                f"the C header's MSIME_CLOUD_{name}_TIMEOUT_MS is {header.get(name)}, and the reference asks for {expected}"
            )

    for path, required, (scope, literal) in HOSTS:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for name in required:
            if name not in text:
                failures.append(f"{path.relative_to(ROOT)} does not read {name}")
        if scope:
            match = re.search(scope, text)
            if not match:
                failures.append(f"{path.relative_to(ROOT)} no longer has the request this checks")
                continue
            # The initialiser runs to the next one at column zero.
            rest = text[match.end() :]
            end = re.search(r"\n- \(", rest)
            text = rest[: end.start()] if end else rest
        for value in re.findall(literal, text):
            failures.append(
                f"{path.relative_to(ROOT)} sets this request's deadline to a literal {value}"
            )
        # A literal beside the call is how the two hosts drifted in the first place. Only lines that
        # *set* this request's deadline count: a line that checks a value the shared layer declared
        # in a descriptor is the host holding the contract, which is the opposite of drift.

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(
        f"cloud request budget: connect {REFERENCE['CONNECT']} ms, total {REFERENCE['REQUEST']} ms, "
        f"read from the shared declaration by {len(HOSTS)} hosts"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
