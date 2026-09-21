#!/usr/bin/env python3
"""Render the launcher icons from the one brand artwork (brew install librsvg).

The artwork lives at `apps/desktop/app-icon.svg` and is the same file the Windows client ships as
`msime.ico`. The themes differ from the default by exactly one value - the colour of the ragged
frame - so they are derived rather than drawn, and the same table is used on iOS.

`classic` is rendered here alongside the themes rather than left as the Lanczos reduction of the
`.ico` it used to be: it now needs the same field and the same inset as everything else, and two
routes to one mark is how they drift apart.
"""
from pathlib import Path
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

# The artwork is a framed portrait panel drawn for the Windows tray, where it floats on whatever is
# behind it and so has to supply its own border. A launcher icon is the opposite case: the launcher
# draws the container. Android masks these legacy drawables less aggressively than iOS does, but the
# two platforms have to show one icon, so the geometry is kept identical - see the iOS script for
# where the numbers come from.
BBOX = (10.3125, 0.3223, 99.6875, 109.6777)
INSET = 0.74


def artwork(frame: str) -> str:
    left, top, right, bottom = BBOX
    scale = INSET * 110 / (bottom - top)
    x, y = 55 - scale * (left + right) / 2, 55 - scale * (top + bottom) / 2
    body = MASTER.read_text().split("\n", 1)[1].replace("</svg>", "")
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
        ' width="110" height="110" viewBox="0 0 110 110" fill="none">\n'
        f'<rect width="110" height="110" fill="{FIELD}"/>\n'
        f'<g transform="translate({x:.4f} {y:.4f}) scale({scale:.6f})">\n{body}</g>\n</svg>\n'
    ).replace(FRAME, frame)


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        for name, frame in VARIANTS.items():
            source = Path(directory) / f"{name}.svg"
            source.write_text(artwork(frame))
            for density, pixels in DENSITIES.items():
                destination = ROOT / f"res/drawable-{density}/app_icon_{name}.png"
                destination.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    ["rsvg-convert", "-w", str(pixels), "-h", str(pixels), str(source),
                     "-o", str(destination)],
                    check=True,
                )


if __name__ == "__main__":
    main()
