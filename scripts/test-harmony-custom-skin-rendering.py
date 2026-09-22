#!/usr/bin/env python3
"""Guard custom skin fields at the real Harmony keyboard rendering boundary."""

from pathlib import Path


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    view = (root / "platforms/harmony/entry/src/main/ets/keyboard/KeyboardView.ets").read_text()
    model = (root / "platforms/harmony/entry/src/main/ets/keyboard/skin/CustomKeyboardSkin.ts").read_text()
    required = {
        "photo preference decoded": "decodePhoto(document.photo)" in model,
        "backdrop mounted": "this.skinBackdrop()" in view,
        "gradient rendered": ".linearGradient({" in view and "this.skin.gradientEnd" in view,
        "photo rendered": "Image(this.skin.photoSource)" in view
            and "this.skin.photoShadeColor()" in view,
        "pattern rendered": "this.drawSkinPattern()" in view
            and "this.skin.patternColor()" in view,
        "shape reaches keys": ".borderRadius(this.skin.keyCornerRadius())" in view,
        "material reaches keys": "this.skin.materialTop()" in view
            and "this.skin.materialBottom()" in view,
        "shadow reaches keys": ".shadow({ radius: this.skin.shadowRadius" in view,
        "fill opacity spares labels": "this.skin.keySurfaceBackground(" in view
            and ".opacity(this.skin.keyOpacity)" not in view,
    }
    problems = [name for name, present in required.items() if not present]
    if problems:
        for problem in problems:
            print(f"missing custom skin rendering guard: {problem}")
        return 1
    print("harmony custom skin: backdrop artwork and key treatments reach the native keyboard")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
