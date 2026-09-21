#!/usr/bin/env python3
"""Render every iOS icon from the one brand artwork with librsvg (brew install librsvg).

The artwork lives at `apps/desktop/app-icon.svg` and is the same file the Windows client ships as
`msime.ico`; it is not duplicated here. The alternate icons differ from the default by exactly one
value - the colour of the ragged frame - so they are derived rather than drawn, and only the
rendered PNGs are kept. Changing the logo means replacing that one master.

The master is transparent outside the frame, which an app icon may not be: iOS applies its own
mask and expects an opaque square. Each rendition is therefore laid over the artwork's own dark
field before rasterising, and inset so the mask has somewhere to bite - see INSET.
"""
import json
from pathlib import Path
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

# The artwork is a framed portrait panel drawn for the Windows tray, where it floats on whatever
# is behind it and so has to supply its own border. An app icon is the opposite case: the platform
# already draws the container, and its rounded mask cuts through anything near the edge. The frame
# comes within 0.32 units of the top of the 110-unit canvas, so shipping the master as-is loses the
# top and bottom of the border and leaves a broken box. Inset the whole artwork instead - the frame
# stays whole and the mask only ever touches the field.
BBOX = (10.3125, 0.3223, 99.6875, 109.6777)  # the master's own extent, off its 1024px rendition
INSET = 0.74  # artwork height as a fraction of the icon; leaves the mask ~13% top and bottom


def transform() -> str:
    left, top, right, bottom = BBOX
    scale = INSET * 110 / (bottom - top)
    return (
        f"translate({55 - scale * (left + right) / 2:.4f} {55 - scale * (top + bottom) / 2:.4f})"
        f" scale({scale:.6f})"
    )


def artwork(frame: str, field: str | None = FIELD) -> str:
    """The master centred in a square. Without a field it keeps the master's own transparency."""
    body = MASTER.read_text().split("\n", 1)[1].replace("</svg>", "")
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
        ' width="110" height="110" viewBox="0 0 110 110" fill="none">\n'
        + (f'<rect width="110" height="110" fill="{field}"/>\n' if field else "")
        + f'<g transform="{transform()}">\n{body}</g>\n</svg>\n'
    ).replace(FRAME, frame)


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
