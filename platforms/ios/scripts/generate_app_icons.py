#!/usr/bin/env python3
"""Render the editable brand SVG variants with librsvg (brew install librsvg)."""
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1] / "App/Resources"
ASSETS = ROOT / "Assets.xcassets"
MARK = 'M25 6.5 7.5 14 24.5 18.25 7.5 25.75c4.5 3.5 10.5 5.25 17.5 2.75'
VARIANTS = {
    "Forest": ("#287B61", "#0A302C", "#ECF7D9", '<circle cx="8" cy="5" r="23" fill="#A8D6A0" opacity=".08"/>'),
    "Sky": ("#70DCF0", "#2665D4", "#FFFFFF", '<path d="M-2 26Q8 20 18 27T38 26V36H-2Z" fill="#FFFFFF" opacity=".12"/>'),
    "Dusk": ("#A896EF", "#40306B", "#FFF0DC", '<circle cx="28" cy="7" r="10" fill="#FAD3DD" opacity=".16"/><circle cx="7" cy="28" r="15" fill="#453D98" opacity=".18"/>'),
    "Vermilion": ("#F2E7D6", "#F2E7D6", "#FFF2DF", '<rect x="2.8" y="4.2" width="26.4" height="27.6" rx="4.5" fill="#B74332"/>'),
}

def catalog(path, filename):
    path.mkdir(parents=True, exist_ok=True)
    entry = {"filename": filename, "idiom": "universal"}
    (path / "Contents.json").write_text(json.dumps({"images": [entry], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def alternate_catalog(path, source):
    # Supply explicit iPhone and iPad renditions, including legacy-size slots.
    path.mkdir(parents=True, exist_ok=True)
    images = []
    for idiom, sizes, scales in [("iphone", [20, 29, 40, 60], [2, 3]), ("ipad", [20, 29, 40, 76], [1, 2]), ("ipad", [83.5], [2])]:
        for size in sizes:
            for scale in scales:
                pixels = str(int(size * scale))
                filename = f"Icon-{pixels}.png"
                subprocess.run(["rsvg-convert", "-w", pixels, "-h", pixels, str(source), "-o", str(path / filename)], check=True)
                images.append({"idiom": idiom, "size": f"{size}x{size}", "scale": f"{scale}x", "filename": filename})
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "Icon.png"})
    (path / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def main():
    for name, (start, end, ink, decoration) in VARIANTS.items():
        # Full-bleed opaque backgrounds; iOS supplies the outer icon mask.
        transform = 'translate(3.2 3.6) scale(.8)' if name == "Vermilion" else 'translate(1.6 1.8) scale(.9)'
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="-2 0 36 36">
  <title>Metasequoia — {name}</title>
  <defs><linearGradient id="background" x2=".8" y2="1"><stop stop-color="{start}"/><stop offset="1" stop-color="{end}"/></linearGradient></defs>
  <path fill="url(#background)" d="M-2 0h36v36H-2z"/>
  {decoration}
  <path d="{MARK}" transform="{transform}" fill="none" stroke="{ink}" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'''
        source = ROOT / "AlternateIcons" / f"{name}.svg"
        source.write_text(svg)
        icon = ASSETS / f"AppIcon{name}.appiconset"
        alternate_catalog(icon, source)
        subprocess.run(["rsvg-convert", str(source), "-o", str(icon / "Icon.png")], check=True)
        preview = ASSETS / f"AppIconPreview{name}.imageset"
        catalog(preview, "Preview.png")
        subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", str(source), "-o", str(preview / "Preview.png")], check=True)
    original = ASSETS / "AppIconPreviewClassic.imageset"
    catalog(original, "Preview.png")
    shutil.copyfile(ASSETS / "AppIcon.appiconset/AppIcon.png", original / "Preview.png")


if __name__ == "__main__":
    main()
