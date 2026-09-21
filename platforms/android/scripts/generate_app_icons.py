#!/usr/bin/env python3
"""Render the launcher icons from the one brand artwork (brew install librsvg).

The artwork lives at `apps/desktop/app-icon.svg` and is the same file the Windows client ships as
`msime.ico`. The themes differ from the default by exactly one value - the colour of the frame -
so they are derived rather than drawn, and the same table is used on iOS.

`classic` is rendered here alongside the themes rather than left as the Lanczos reduction of the
`.ico` it used to be: it now needs the same field and the same inset as everything else, and two
routes to one mark is how they drift apart.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT.parents[1] / "apps/desktop/app-icon.svg"

FRAME = "#A8DF8E"
FIELD = "#252525"
# Shared with platforms/ios/scripts/generate_app_icons.py; the two launchers show the same themes.
VARIANTS = {"classic": FRAME, "forest": "#287B61", "sky": "#70DCF0",
            "dusk": "#A896EF", "vermilion": "#B74332"}
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# The artwork was drawn for the Windows tray: it floats on whatever is behind it, so it supplies its
# own border, painted as scattered brush stamps. A launcher icon is the opposite case on both counts
# - the launcher draws the container, and at these sizes the brush's ragged alpha reads as a smeared
# edge. Android masks legacy drawables less aggressively than iOS does, but the two platforms have to
# show one icon, so the geometry is identical; the iOS script is where the numbers are explained.
INSET = 0.74
FRAME_WIDTH = 5
# The adaptive layers. A circular mask shows only the middle 72 of the 108dp canvas, and a square
# fits inside that disc up to 72/sqrt(2) ~= 51 -- so the mark goes at 47%, not at the 66dp safe zone,
# which is sized for artwork that tolerates having its corners cut. This frame is what must not be.
FOREGROUND_INSET = 0.47
FOREGROUND_DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216,
                        "xxhdpi": 324, "xxxhdpi": 432}
PANEL = re.compile(r'<path d="(M15 5H95V105H15V5Z)" fill="#252525"/>')
MARK = re.compile(r'<path d="M74\.[^"]*" stroke="white"[^>]*/>')


def artwork(frame: str, inset: float = INSET, backdrop: bool = True) -> str:
    master = MASTER.read_text()
    panel, mark = PANEL.search(master), MARK.search(master)
    if not panel or not mark:
        raise SystemExit(f"{MASTER} no longer has the panel and mark this script composes")
    rect = panel.group(1)
    half = FRAME_WIDTH / 2
    left, top, right, bottom = 15 - half, 5 - half, 95 + half, 105 + half
    scale = inset * 110 / (bottom - top)
    x, y = 55 - scale * (left + right) / 2, 55 - scale * (top + bottom) / 2
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="110" height="110" viewBox="0 0 110 110"'
        ' fill="none">\n'
        + (f'<rect width="110" height="110" fill="{FIELD}"/>\n' if backdrop else '')
        + f'<g transform="translate({x:.4f} {y:.4f}) scale({scale:.6f})">\n'
        f'<path d="{rect}" fill="{FIELD}"/>\n'
        f'<path d="{rect}" fill="none" stroke="{frame}" stroke-width="{FRAME_WIDTH}"/>\n'
        f"{mark.group(0)}\n</g>\n</svg>\n"
    )


def render(source: Path, pixels: int, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(pixels), "-h", str(pixels), str(source), "-o", str(destination)],
        check=True,
    )


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        for name, frame in VARIANTS.items():
            source = Path(directory) / f"{name}.svg"
            source.write_text(artwork(frame))
            for density, pixels in DENSITIES.items():
                render(source, pixels, ROOT / f"res/drawable-{density}/app_icon_{name}.png")
            # The adaptive foreground carries no field of its own: the background layer is that
            # field, so the mask cuts through it rather than through a plate the launcher invents.
            layer = Path(directory) / f"{name}-foreground.svg"
            layer.write_text(artwork(frame, FOREGROUND_INSET, backdrop=False))
            for density, pixels in FOREGROUND_DENSITIES.items():
                render(layer, pixels,
                       ROOT / f"res/drawable-{density}/app_icon_{name}_foreground.png")


if __name__ == "__main__":
    main()
