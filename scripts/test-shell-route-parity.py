#!/usr/bin/env python3
"""Check that every surface route the Windows Server emits is one the shell parses.

The tray menu and the floating toolbar hand the shared Tauri shell a route string. C++ builds it
(`platforms/windows/src/system/ShellSurfaces.h`) and Rust consumes it
(`crates/client-core/src/host_surface.rs`). Each side has its own tests, and each passes on its own
vocabulary, so a name that is changed on one side and not the other breaks nothing visibly: an
unparseable route is not an error, it opens the ordinary settings window. The row still works,
it just opens the wrong thing.

The Linux launcher emits the same contract, so this covers it too.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EMITTER = ROOT / "platforms/windows/src/system/ShellSurfaces.h"
PARSER = ROOT / "crates/client-core/src/host_surface.rs"


def emitted() -> tuple[set[str], set[str]]:
    """The panel names and settings sections `shell_surface_request` can return."""
    text = EMITTER.read_text()
    body = text[text.index("shell_surface_request(TrayMenuCommand command)") :]
    body = body[: body.index("\n}")]
    panels: set[str] = set()
    pages: set[str] = set()
    # ShellSurfaceRequest{"panel", "page"}, where either half may be the empty `{}`.
    half = r'("(?:[^"]*)"|\{\})'
    pattern = r"ShellSurfaceRequest\{\s*" + half + r"\s*,\s*" + half + r"\s*\}"
    found = re.findall(pattern, body)
    if not found:
        raise SystemExit(f"no route literals found in {EMITTER.name}; the extraction is wrong")
    for panel, page in found:
        for raw, into in ((panel, panels), (page, pages)):
            if raw == "{}":
                continue
            name = raw.strip('"')
            if name:
                into.add(name)
    return panels, pages


def parsed() -> tuple[set[str], set[str]]:
    """The route heads and settings sections Rust accepts."""
    text = PARSER.read_text()

    def arms(after: str) -> set[str]:
        body = text[text.index(after) :]
        body = body[: body.index("_ => Err(RouteError::Unknown)")]
        return {name for name in re.findall(r'"([^"]+)" => Ok\(', body)}

    routes = arms('"settings" => Ok(SurfaceRoute::Settings(None))')
    categories = arms('"account" => Ok(SettingsCategory::Account)')
    return routes, categories


def main() -> int:
    panels, pages = emitted()
    routes, categories = parsed()
    if not panels or not pages or not routes or not categories:
        print("route parity: one side produced no names; the extraction is wrong", file=sys.stderr)
        return 1

    failures = []
    for panel in sorted(panels):
        if panel not in routes:
            failures.append(
                f"the Windows Server emits the panel route {panel!r}, which SurfaceRoute::parse "
                f"does not accept; that row would open the settings window instead"
            )
    for page in sorted(pages):
        if page not in categories:
            failures.append(
                f"the Windows Server emits the settings section {page!r}, which "
                f"SettingsCategory::parse does not accept; that row would open the default section"
            )
    if failures:
        for failure in failures:
            print(f"route parity: {failure}", file=sys.stderr)
        return 1

    print(
        f"shell route parity: {len(panels)} panel routes and {len(pages)} settings sections "
        f"are all accepted by the shell"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
