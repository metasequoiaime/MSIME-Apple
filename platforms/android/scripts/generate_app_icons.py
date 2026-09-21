#!/usr/bin/env python3
"""Render the themed launcher icons from the one brand artwork (brew install librsvg).

The artwork lives at `apps/desktop/app-icon.svg` and is the same file the Windows client ships as
`msime.ico`. The themes differ from the default by exactly one value - the colour of the ragged
frame - so they are derived rather than drawn, and the same table is used on iOS.

`app_icon_classic.png` is left alone: it is already this artwork, rendered by whoever first brought
the mark over, and re-rendering it here would churn five files to no effect.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT.parents[1] / "apps/desktop/app-icon.svg"

FRAME = "#A8DF8E"
# Shared with platforms/ios/scripts/generate_app_icons.py; the two launchers show the same themes.
VARIANTS = {"forest": "#287B61", "sky": "#70DCF0", "dusk": "#A896EF", "vermilion": "#B74332"}
# Android draws its own background behind these, so the artwork keeps its transparent margin -
# unlike iOS, which masks an opaque square and needs the field filled in.
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def main() -> None:
    master = MASTER.read_text()
    with tempfile.TemporaryDirectory() as directory:
        for name, frame in VARIANTS.items():
            source = Path(directory) / f"{name}.svg"
            source.write_text(master.replace(FRAME, frame))
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
