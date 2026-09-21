#!/usr/bin/env python3
"""Run the Windows test sources that do not actually need Windows.

Most of `platforms/windows/tests/` is policy: pure functions over contract
structs, with no Win32 call anywhere in the translation unit. On a machine with
no Windows and no Docker those tests had exactly one level of evidence - the
cross build linked them - and linking does not catch an assertion. That is the
whole gap this closes: the same sources, compiled with the host compiler and
actually executed.

Which ones qualify is discovered rather than listed. A source that compiles and
links on its own with the host compiler is one whose translation unit needs
nothing from Windows; anything that does not is skipped and stays covered by the
cross build alone. Nothing has to be added here when a test is added.

Three sources compile but do not pass here, and they are exclusions with reasons
rather than failures - see `HOST_DIFFERENCES`. Every other failure is reported:
these are the same assertions the Windows build would make.
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "platforms/windows/tests"
SRC = ROOT / "platforms/windows/src"

# Sources that build here but cannot pass here. Each is a property of the host,
# not of the code, and each is still executed by the cross build's own runners.
HOST_DIFFERENCES = {
    "runtime/aux_message.cpp": (
        "wchar_t is 4 bytes here and 2 on Windows, so the wire bytes a test "
        "builds from a wide literal are a different shape and the "
        "embedded-NUL case cannot be expressed"
    ),
    "ui/shell_surfaces.cpp": "asserts on Windows path and environment-block semantics",
    "runtime/session_pump.cpp": (
        "does not compile here: it takes a path's u8string(), which is "
        "std::u8string, where the Windows build's own conversion applies"
    ),
    "runtime/session_smoke.cpp": (
        "does not compile here: it calls preference_monitor_tests, declared "
        "only for the Windows build"
    ),
}

# Sources whose `main` takes an argument the build system supplies.
ARGUMENTS = {
    "core/installer_launch.cpp": ["platforms/windows/installer/msime_setup.iss"],
}

# The three online workers are the exception to "one translation unit": their
# class bodies live in a .cpp of their own, so a test of the queueing above them
# links that file too. Every one of those files reaches the shared host library
# for its request building, which is why this is a named list rather than a rule
# - linking arbitrary sources would drag the whole Windows build in. When the
# host library has not been built here the three are skipped exactly like any
# other source that needs more than itself.
COMPANIONS = {
    "candidate/cloud_candidate_worker.cpp": ["candidate/CloudCandidateWorker.cpp"],
    "candidate/ai_candidate_worker.cpp": ["candidate/AiCandidateWorker.cpp"],
    "candidate/translation_worker.cpp": ["candidate/TranslationWorker.cpp"],
}
COMPANION_LIBRARIES = ["-lcurl", "-lsqlite3"]
COMPANION_FRAMEWORKS = [
    "CoreFoundation",
    "CoreText",
    "CoreGraphics",
    "Security",
    "SystemConfiguration",
]


def host_library() -> pathlib.Path | None:
    """The shared host library the worker sources link against, if it is built."""
    for profile in ("debug", "release"):
        candidate = ROOT / "target" / profile / "libmsime_host_api.a"
        if candidate.exists():
            return candidate
    return None


def companion_flags(relative: str) -> list[str] | None:
    """Extra compiler arguments for a source that needs its class body, or None."""
    companions = COMPANIONS.get(relative)
    if not companions:
        return []
    library = host_library()
    if library is None:
        return None
    flags = [str(SRC / name) for name in companions]
    flags += [str(library), *COMPANION_LIBRARIES]
    if sys.platform == "darwin":
        for framework in COMPANION_FRAMEWORKS:
            flags += ["-framework", framework]
    return flags

EXTRA_INCLUDES = ["/opt/homebrew/include", "/usr/local/include"]


def cmake_sources() -> set[str]:
    """Every test source the Windows build actually compiles.

    A file under `tests/` that no CMakeLists mentions is not a test of this
    build - `voice/voice_wire_peer.cpp` is a subprocess fixture driven by a Rust
    interop test, and running it as though it were a test reports a pass for
    something that never asserted anything.
    """
    mentioned: set[str] = set()
    for lists in sorted((ROOT / "platforms/windows").rglob("CMakeLists.txt")):
        text = lists.read_text(encoding="utf-8")
        for source in TESTS.rglob("*.cpp"):
            relative = source.relative_to(ROOT / "platforms/windows").as_posix()
            if relative in text or source.name in text:
                mentioned.add(source.relative_to(TESTS).as_posix())
    return mentioned


def include_flags() -> list[str]:
    # Every source directory, the way the Windows build exposes them, plus the
    # contract and host headers. Derived so a new subdirectory needs no edit.
    directories = [SRC, *(path for path in sorted(SRC.iterdir()) if path.is_dir())]
    directories += [TESTS / "core", ROOT / "vendor/MSIME-Engine/contracts", ROOT / "crates/host-api/include"]
    flags = [f"-I{path}" for path in directories if path.exists()]
    flags += [f"-I{path}" for path in EXTRA_INCLUDES if pathlib.Path(path).exists()]
    return flags


def build(
    source: pathlib.Path, flags: list[str], workspace: pathlib.Path
) -> tuple[pathlib.Path | None, str]:
    """(executable, reason). A null executable with a reason is a failure to report."""
    relative = source.relative_to(TESTS).as_posix()
    binary = workspace / relative.replace("/", "_").removesuffix(".cpp")
    companions = companion_flags(relative)
    if companions is None:
        return None, ""
    # Compiling is CPU-bound and safe to do many at once.
    compiled = subprocess.run(
        ["c++", "-std=c++20", "-w", *flags, "-o", str(binary), str(source), *companions],
        capture_output=True,
        text=True,
    )
    if compiled.returncode == 0:
        return binary, ""
    # Two ordinary reasons a test source does not build on its own here, both
    # of them "the Windows build owns this one":
    #   - it reaches for a Windows header;
    #   - it needs the other translation units the Windows build links it with,
    #     which shows up as undefined symbols.
    # Anything else is code that does not compile, and letting that quietly
    # leave the count is exactly how a suite goes missing - the failure this
    # runner exists to stop happening, so it is reported rather than skipped.
    ordinary = (
        "file not found",
        "No such file or directory",
        "Undefined symbols",
        "undefined reference",
    )
    if any(marker in compiled.stderr for marker in ordinary):
        return None, ""
    if source.relative_to(TESTS).as_posix() in HOST_DIFFERENCES:
        return None, ""
    first = next(
        (line for line in compiled.stderr.splitlines() if "error" in line),
        "did not compile",
    )
    return None, first[:200]


def execute(source: pathlib.Path, binary: pathlib.Path) -> tuple[str, str]:
    """Returns (outcome, detail) where outcome is passed / failed / excluded."""
    relative = source.relative_to(TESTS).as_posix()
    if relative in HOST_DIFFERENCES:
        return "excluded", HOST_DIFFERENCES[relative]
    try:
        run = subprocess.run(
            [str(binary), *ARGUMENTS.get(relative, [])],
            capture_output=True,
            text=True,
            timeout=120,
            cwd=ROOT,
            # Never the caller's stdin. A fixture that reads frames from it
            # blocks forever on whatever the gate happened to be started with,
            # which is how this runner first hung.
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        return "failed", "timed out"
    if run.returncode == 0:
        return "passed", ""
    detail = (run.stderr.strip() or run.stdout.strip() or "no output").splitlines()
    return "failed", detail[0][:200] if detail else "no output"


def main() -> int:
    if shutil.which("c++") is None:
        print("skipped: no host C++ compiler")
        return 0
    if not TESTS.exists():
        print("skipped: the Windows tests are not present")
        return 0
    flags = include_flags()
    built_by_cmake = cmake_sources()
    sources = [
        source
        for source in sorted(TESTS.rglob("*.cpp"))
        if source.relative_to(TESTS).as_posix() in built_by_cmake
    ]
    fixtures = len(list(TESTS.rglob("*.cpp"))) - len(sources)
    with tempfile.TemporaryDirectory() as directory:
        workspace = pathlib.Path(directory)
        with ThreadPoolExecutor(max_workers=os.cpu_count()) as pool:
            builds = list(pool.map(lambda source: build(source, flags, workspace), sources))
        # Run one at a time. Some of these wait on their own timers - a worker's
        # debounce window, a lease deadline - and a gate that reds because the
        # machine was busy is a gate people learn to skip. Serial execution costs
        # a couple of seconds and removes the whole class.
        outcomes = [
            (
                source,
                *(
                    execute(source, binary)
                    if binary
                    else (("failed", reason) if reason else ("skipped", ""))
                ),
            )
            for source, (binary, reason) in zip(sources, builds)
        ]

    failures = [
        (source.relative_to(ROOT).as_posix(), detail)
        for source, outcome, detail in outcomes
        if outcome == "failed"
    ]
    counts = {name: 0 for name in ("passed", "failed", "skipped", "excluded")}
    for _, outcome, _ in outcomes:
        counts[outcome] += 1

    for name, detail in failures:
        print(f"FAIL {name}: {detail}", file=sys.stderr)
    if failures:
        print(
            "\nThese are the assertions the Windows build makes, running here. A failure that is "
            "a property of this host rather than of the code belongs in HOST_DIFFERENCES with the "
            "reason written out.",
            file=sys.stderr,
        )
        return 1
    print(
        f"windows native run: {counts['passed']} passed, "
        f"{counts['excluded']} excluded by host differences, "
        f"{counts['skipped']} need the Windows build, "
        f"{fixtures} not tests"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
