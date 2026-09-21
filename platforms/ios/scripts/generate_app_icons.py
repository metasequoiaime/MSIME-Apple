#!/usr/bin/env python3
"""Render every iOS icon from the one brand artwork with librsvg (brew install librsvg).

The artwork lives at `apps/desktop/app-icon.svg` and is the same file the Windows client ships as
`msime.ico`; it is not duplicated here. The alternate icons differ from the default by exactly one
value - the colour of the frame - so they are derived rather than drawn, and only the rendered PNGs
are kept. Changing the logo means replacing that one master.

Two things the master cannot be used for as-is, both consequences of it having been drawn for the
Windows tray rather than for a home screen; see FRAME_WIDTH and INSET.
"""
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1] / "App/Resources"
ASSETS = ROOT / "Assets.xcassets"
MASTER = Path(__file__).resolve().parents[3] / "apps/desktop/app-icon.svg"

FRAME = "#A8DF8E"
FIELD = "#252525"
# One colour each, taken from the theme's own palette and far enough from the default's light
# green to be told apart at home-screen size.
VARIANTS = {"Forest": "#287B61", "Sky": "#70DCF0", "Dusk": "#A896EF", "Vermilion": "#B74332"}

# In the tray the icon floats on whatever is behind it, so it carries its own border, and that
# border is painted as 164 scattered brush stamps along the panel's edge. An app icon is the
# opposite case on both counts.
#
# The platform draws the container and its rounded mask cuts through anything near the edge. The
# master's frame comes within 0.32 units of the top of the 110-unit canvas, so shipping it at its
# native extent loses the top and bottom of the border and leaves a broken box. Inset it instead.
INSET = 0.74  # artwork height as a fraction of the icon; leaves the mask ~13% top and bottom
# A home-screen icon is 180px, where the frame lands about four pixels wide. The brush's ragged
# alpha and the dark gaps between stamps have nowhere to go at that width and read as a smeared
# edge rather than as texture. The stamps are therefore replaced by one stroke on the same path,
# at the weight the brush band carried (measured at 1024: a ~6.5 unit band over a ~5 unit core).
FRAME_WIDTH = 5

# The two top-level paths of the master, in order: the dark panel and the white mark. Everything
# else in the file is the scatter - the 164 `use` elements and the `defs` they point at.
PANEL = re.compile(r'<path d="(M15 5H95V105H15V5Z)" fill="#252525"/>')
MARK = re.compile(r'<path d="M74\.[^"]*" stroke="white"[^>]*/>')


def parts() -> tuple[str, str]:
    master = MASTER.read_text()
    panel, mark = PANEL.search(master), MARK.search(master)
    if not panel or not mark:
        raise SystemExit(f"{MASTER} no longer has the panel and mark this script composes")
    return panel.group(1), mark.group(0)


def artwork(frame: str, field: str | None = FIELD) -> str:
    """The mark in a crisp frame, centred in a square. Without a field it stays transparent."""
    rect, mark = parts()
    half = FRAME_WIDTH / 2  # the stroke straddles the path, so it widens the artwork's extent
    left, top, right, bottom = 15 - half, 5 - half, 95 + half, 105 + half
    scale = INSET * 110 / (bottom - top)
    transform = (
        f"translate({55 - scale * (left + right) / 2:.4f} {55 - scale * (top + bottom) / 2:.4f})"
        f" scale({scale:.6f})"
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="110" height="110" viewBox="0 0 110 110"'
        ' fill="none">\n'
        + (f'<rect width="110" height="110" fill="{field}"/>\n' if field else "")
        + f'<g transform="{transform}">\n'
        f'<path d="{rect}" fill="{FIELD}"/>\n'
        f'<path d="{rect}" fill="none" stroke="{frame}" stroke-width="{FRAME_WIDTH}"/>\n'
        f"{mark}\n</g>\n</svg>\n"
    )


def render(source: Path, destination: Path, pixels: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(pixels), "-h", str(pixels), str(source), "-o", str(destination)],
        check=True,
    )


def preview(name: str, source: Path) -> None:
    path = ASSETS / f"AppIconPreview{name}.imageset"
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(
        json.dumps(
            {"images": [{"filename": "Preview.png", "idiom": "universal"}],
             "info": {"author": "xcode", "version": 1}},
            indent=2,
        ) + "\n"
    )
    render(source, path / "Preview.png", 256)


def alternate(name: str, source: Path) -> None:
    """Explicit iPhone and iPad renditions, including the legacy-size slots."""
    path = ASSETS / f"AppIcon{name}.appiconset"
    path.mkdir(parents=True, exist_ok=True)
    images = []
    for idiom, sizes, scales in [
        ("iphone", [20, 29, 40, 60], [2, 3]),
        ("ipad", [20, 29, 40, 76], [1, 2]),
        ("ipad", [83.5], [2]),
    ]:
        for size in sizes:
            for scale in scales:
                pixels = int(size * scale)
                filename = f"Icon-{pixels}.png"
                render(source, path / filename, pixels)
                images.append(
                    {"idiom": idiom, "size": f"{size}x{size}", "scale": f"{scale}x",
                     "filename": filename}
                )
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x",
                   "filename": "Icon.png"})
    render(source, path / "Icon.png", 1024)
    (path / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        staging = Path(directory)

        default = staging / "AppIcon.svg"
        default.write_text(artwork(FRAME))
        render(default, ASSETS / "AppIcon.appiconset/AppIcon.png", 1024)
        preview("Classic", default)
        # The launch screen, the welcome page and the about page all show the mark on a light
        # background, at a size where the frame reads as part of it. Nothing masks it there, so it
        # keeps the master's transparency rather than sitting on a hard dark square.
        logo = staging / "Logo.svg"
        logo.write_text(artwork(FRAME, field=None))
        render(logo, ASSETS / "MSIMELogo.imageset/logo.png", 1024)

        for name, frame in VARIANTS.items():
            source = staging / f"{name}.svg"
            source.write_text(artwork(frame))
            alternate(name, source)
            preview(name, source)


if __name__ == "__main__":
    main()
