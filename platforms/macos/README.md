# macOS frontend

This directory contains the released InputMethodKit frontend for Metasequoia IME:

- `src/` owns InputMethodKit event routing, the native candidate panel, preferences, input-source registration, and Sparkle integration.
- `resources/` owns the input-method plist, icons, localizations, and installer distribution template.
- `scripts/` owns macOS build, install, uninstall, signing-mode, packaging, appcast, and release helpers.
- `tests/` owns macOS routing, UI-controller, installation, packaging, and release-automation coverage.

The repository root remains the CMake source directory because it integrates the shared engine archive and common legal/version metadata. Build and install from the repository root:

```sh
./platforms/macos/scripts/build.sh
./platforms/macos/scripts/install.sh
```

This frontend may depend on `MetasequoiaImeEngine`, but the engine must not depend on this directory or import Apple frameworks. iOS UI and lifecycle code belongs in `../ios/`, not here.
