# Controlled TSF edit control

This directory contains a small native Win32 editor host for repeatable Windows
TSF checks. It exercises Direct2D/DirectWrite rendering, pre-edit display
attributes, candidate positioning, selection, caret movement, soft wrapping,
mouse hit testing, and the production TSF service boundary from a controlled
editor surface.

It is a verification tool, not a product component. It does not register the
IME, start the production server, or replace validation in third-party
editors. A successful cross-build proves only that the target can compile and
link; real TSF and editor interaction still require a Windows run.

The source was imported from `MSIME-Windows` commit
`345cb87a3822f6ad7013bb29506fe3d856c1931a`.
