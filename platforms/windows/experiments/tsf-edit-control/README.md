# Controlled TSF edit control

This directory contains a small native Win32 editor host for repeatable Windows TSF checks. It builds a `msime-tsf-edit-control` library and a `msime-tsf-edit-control-demo` window that exercise Direct2D/DirectWrite rendering, pre-edit display attributes, candidate positioning, selection, caret movement, soft wrapping, mouse hit testing, and the production TSF service boundary from a controlled editor surface.

It is an experiment and a verification tool, not a product component: it ships in neither the installer nor any package, it does not register the IME, it does not start the production Server, and it does not replace checks in third-party editors. It exists because third-party editors differ in how they drive TSF, so a surface whose behaviour is fully known makes a regression attributable to the TIP rather than to the editor.

It is built with the rest of the platform under `if(WIN32)` and registers no CTest entry — it is driven by hand. Cross-building it confirms that it compiles and links; the interaction it is for happens on Windows.

The source was imported from `MSIME-Windows` commit `345cb87a3822f6ad7013bb29506fe3d856c1931a`.
