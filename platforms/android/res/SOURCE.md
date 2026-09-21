# App icon sources

`app_icon_classic` is derived from metasequoiaime/MSIME-Windows commit
`253b0689` (`windows/image/msime.ico`), the mark the Windows frontend ships.

The `.ico` carries twelve sizes from 16 to 256 square. The 256 square one is the
source; the five Android densities are Lanczos reductions of it, keeping the
alpha channel so the rounded corners stay transparent:

| Density | Size |
| --- | --- |
| mdpi | 48 |
| hdpi | 72 |
| xhdpi | 96 |
| xxhdpi | 144 |
| xxxhdpi | 192 |

`app_icon_forest`, `app_icon_sky`, `app_icon_dusk` and `app_icon_vermilion` are
the same mark with its border in the hue each style has always meant: green,
blue, violet and red. Only the border carries hue — the dark body and the white
stroke are shared — which is what makes the five read as one design rather than
as five unrelated icons.

This paragraph used to say those four were the earlier watercolour 杉 and not
derived from this source. That stopped being true when they were replaced, and
a provenance note that describes assets which are no longer there is worse than
none.

Both repositories are metasequoiaime's own and share its licence; no third-party
distribution restriction applies to this asset.

## Adaptive icons

Each style also ships an `<adaptive-icon>` in `drawable-anydpi-v26`, because a
plain bitmap gets the launcher's legacy treatment: shrunk and set on a grey
plate the design never asked for. The background layer is the mark's own dark
field, so what the mask cuts is that field rather than a plate.

The foreground places the mark at 50% of the 108dp canvas. A circular mask shows
only the middle 72dp, and a square fits inside that disc up to 72/√2 ≈ 51dp — the
66dp safe zone is meant for artwork that tolerates clipping, and this mark's
frame is the part that must not be clipped.
