# App icon sources

All five launcher icons are derived from `apps/desktop/app-icon.svg`, the vector the Windows
frontend ships as `windows/image/msime.ico` (metasequoiaime/MSIME-Windows commit `253b0689`).
`platforms/android/scripts/generate_app_icons.py` renders them; nothing here is hand-edited.

`app_icon_classic` is the artwork's own light green frame. `app_icon_forest`, `app_icon_sky`,
`app_icon_dusk` and `app_icon_vermilion` differ from it by exactly one value - the colour of that
frame - and stay the alternate styles the 我的 tab offers. The same table drives the iOS alternate
icons, so the two platforms show one icon in five washes.

The artwork was drawn for the Windows tray, where it floats on whatever is behind it and so
supplies its own border. Launcher and home-screen icons already sit in a container whose mask cuts
through anything near the edge, so the script insets the artwork to 74% of the square and lays it
on the mark's own dark field. Shipping the master at its native extent loses the top and bottom of
the frame.

| Density | Size |
| --- | --- |
| mdpi | 48 |
| hdpi | 72 |
| xhdpi | 96 |
| xxhdpi | 144 |
| xxxhdpi | 192 |

Both repositories are metasequoiaime's own and share its licence; no third-party distribution
restriction applies to this asset.
