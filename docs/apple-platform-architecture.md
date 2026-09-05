# Apple platform architecture

## Goal

Metasequoia IME uses one composition engine across macOS and iOS, with a separate native frontend for each platform. The shared layer owns input-method behavior; platform layers own operating-system integration and presentation.

This repository is named `MSIME-Apple` because it contains Apple-platform adapters and applications. The reusable engine remains in the independent `MetasequoiaImeEngine` repository so Windows, Apple, and future frontends do not depend on an Apple application project.

## Ownership boundaries

| Layer | Owns | Must not own |
|---|---|---|
| `MetasequoiaImeEngine` | Composition state, schemes, candidate generation, candidate selection, punctuation policy, learning, dictionary access | AppKit, UIKit, InputMethodKit, text-document APIs, platform windows |
| Apple bridge | Stable C++/Objective-C++ boundary, UTF-8/String conversion, platform-neutral result models | Candidate window state, preferences UI, operating-system lifecycle |
| macOS frontend | InputMethodKit events, marked text, native candidate panel, macOS settings, registration, Sparkle updates | A second composition state machine or copied engine policy |
| iOS keyboard extension | `UIInputViewController`, key grid, candidate UI, `textDocumentProxy`, next-keyboard control, extension lifecycle | macOS update/registration code or persistent engine behavior duplicated in Swift |
| iOS host app | Onboarding, keyboard-enablement guidance, settings, privacy disclosure, optional App Group migration | Direct insertion into another app's document |

The engine is the only authority for a composition and its candidates. A platform frontend translates native events into engine calls, renders the returned state, and inserts committed text through the platform API.

```text
MetasequoiaImeEngine (C++17)
          |
          v
shared/apple-bridge
       /       \
      v         v
macOS frontend  iOS keyboard extension
InputMethodKit  UIInputViewController
      |         |
      v         v
macOS settings  iOS host app/settings
```

## Target repository layout

The migration will converge on this layout:

```text
MSIME-Apple/
├── platforms/
│   ├── macos/
│   │   ├── src/
│   │   ├── resources/
│   │   ├── scripts/
│   │   └── tests/
│   └── ios/
│       ├── App/
│       │   ├── Sources/
│       │   └── Resources/
│       ├── KeyboardExtension/
│       │   ├── Sources/
│       │   └── Resources/
│       ├── SharedUI/
│       └── tests/
├── shared/
│   └── apple-bridge/
│       ├── include/
│       ├── src/
│       └── tests/
├── vendor/
│   ├── MetasequoiaImeEngine/
│   └── MetasequoiaImeDict/out/   # 从 MSIME-Dict release 下载，非 submodule
├── cmake/
├── docs/
└── CMakeLists.txt
```

`SharedUI` is limited to intentionally identical iOS app/extension components such as colors and small Swift value types. It is not shared with macOS. UI code is not moved into the C++ engine.

## iOS operating constraints

The iOS frontend is a custom keyboard extension. It inserts and removes text only through `textDocumentProxy`, and it must expose the system next-keyboard action when required. Secure text fields, phone-pad fields, and applications that reject third-party keyboards can replace or disable the extension; those are operating-system boundaries rather than engine failures.

The keyboard runs entirely on-device without Open Access. The host app and keyboard extension use a narrowly scoped App Group for shared settings, beginning with the input-scheme choice. `RequestsOpenAccess` remains disabled, and network access is not part of the base architecture.

Extension memory and startup time are stricter than on macOS. The bridge therefore creates engine state lazily, avoids background services, and tears down platform objects with the extension lifecycle. Dictionary packaging and memory measurements must be verified on a real device before declaring the iOS frontend production-ready.

## Stable product identities

Repository and source-directory names may change, but these published identities remain stable unless a migration is designed separately:

- macOS bundle and input-source identifiers
- macOS application name `MetasequoiaIME.app`
- existing release asset names and Sparkle signing key
- user preferences and learned-data locations
- engine database and user-dictionary formats

The canonical update feed uses the renamed repository URL. GitHub redirects the previous repository URL, so already released macOS builds continue to find updates.

The iOS host app, keyboard extension, App Group, and signing identifiers will be introduced as new identities. They must not reuse the macOS input-source identifier.

## Pull-request sequence

Each step must leave the existing macOS release build usable:

1. Move the platform-neutral input session into `MetasequoiaImeEngine` and consume it from macOS.
2. Rename the repository and document the cross-platform ownership boundaries.
3. Move the current macOS files under `platforms/macos/`; update build, packaging, release, and test paths without changing behavior.
4. Add the iOS host app and keyboard-extension shell, including onboarding and the required next-keyboard control. Keep input local and use a deterministic placeholder layout until the engine bridge is connected.
5. Add `shared/apple-bridge`, link the engine into the keyboard extension, and cover character input, backspace, raw commit, leading-candidate commit, cancel, and candidate selection.
6. Add the native iOS candidate surface and device-level keyboard interaction tests.
7. Add settings and dictionary/language features incrementally, introducing App Group or Open Access only when a reviewed requirement needs them.

Behavior changes are not bundled into directory-move pull requests. macOS and iOS UI work remain separate so each can be reviewed and verified against its platform lifecycle.

## Verification gates

The root CI will eventually contain two independent jobs:

- macOS: arm64 and x86_64 CMake build, shared-engine tests, native frontend tests, bundle validation, signing validation, and release-package tests.
- iOS: iPhone Simulator build for the host app and keyboard extension, bridge tests, extension Info.plist validation, and UI smoke tests through the Orca iOS emulator.

Shared-engine behavior is tested in `MetasequoiaImeEngine`. Apple bridge tests verify type conversion and lifecycle boundaries. Platform tests verify event routing and native UI behavior without copying the engine's candidate policy tests.
