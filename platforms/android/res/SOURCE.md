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
the same mark with its border remapped to the hue each style has always meant:
green, blue, violet and red respectively, sampled from the watercolour 杉 icons
they replace. Only the border carries hue — the dark body and the white stroke
fall outside the saturation band the remap touches, so all five read as one
design rather than as five.

Both repositories are metasequoiaime's own and share its licence; no third-party
distribution restriction applies to this asset.
