# Metasequoia IME for Apple platforms

[中文 README](README.md) · [Website](https://msime.app) · [Docs](https://msime.app/docs/) · [Privacy](PRIVACY.md)

<!-- badges:start -->
[![CI](https://img.shields.io/github/actions/workflow/status/metasequoiaime/MSIME-Apple/ci.yml?branch=develop&label=CI)](https://github.com/metasequoiaime/MSIME-Apple/actions/workflows/ci.yml)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/metasequoiaime/MSIME-Apple/codeql.yml?branch=develop&label=CodeQL)](https://github.com/metasequoiaime/MSIME-Apple/actions/workflows/codeql.yml)
[![macOS](https://img.shields.io/github/v/release/metasequoiaime/MSIME-Apple?include_prereleases&filter=macos-*&label=macOS)](https://github.com/metasequoiaime/MSIME-Apple/releases)
[![iOS](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmetasequoiaime%2FMSIME-Apple%2Fdevelop%2Fplatforms%2Fios%2Fproject.yml&query=%24.settings.base.MARKETING_VERSION&prefix=v&label=iOS&color=inactive)](docs/ios-distribution.md)
[![License](https://img.shields.io/github/license/metasequoiaime/MSIME-Apple)](LICENSE)
[![Stars](https://img.shields.io/github/stars/metasequoiaime/MSIME-Apple?style=flat)](https://github.com/metasequoiaime/MSIME-Apple/stargazers)
<!-- badges:end -->

A Chinese and Japanese input method for macOS and iOS. The macOS frontend is an InputMethodKit input source with AppKit UI; iOS is a host app with a keyboard extension. Both share the C++ conversion engine used by the Windows and Linux frontends, which lives in [MSIME-Engine](https://github.com/metasequoiaime/MSIME-Engine) and is pinned here as a submodule.

**This is a public beta.**

## Install (macOS)

Download from [Releases](https://github.com/metasequoiaime/MSIME-Apple/releases): either the `.pkg`, or the `.zip` — unpack that one into `~/Library/Input Methods`. Then enable "水杉输入法" under System Settings → Keyboard → Text Input → Edit.

Current builds are **not notarized and not Developer ID signed**; the file names say `unsigned`. Gatekeeper blocks them on first launch and you have to allow the app explicitly under System Settings → Privacy & Security. Every release ships a `.sha256` next to each asset — check it with `shasum -a 256` before installing.

Updates go through [Sparkle](https://sparkle-project.org), from the app's own "Check for Updates…" menu item. The appcast is signed and verified against the project's Ed25519 key before anything is unpacked, so the update path is authenticated even though the build itself is not yet Developer ID signed.

## iOS

The iOS target builds and is exercised in CI on the simulator, but **it is not distributed**, and that is a licensing constraint rather than an unfinished feature. A custom keyboard can only reach users through the App Store or TestFlight, and the App Store terms impose device limits and DRM that GPL-3.0 §6 does not permit — the reason VLC and GNU Go were pulled in 2010. A §7 exception could cover this project's own code, but the bundled `msime.db` is built from [rime-ice](https://github.com/iDvel/rime-ice), which is GPL-3.0 and whose exception only its copyright holders can grant. [`docs/ios-distribution.md`](docs/ios-distribution.md) lays out the options and their costs, and records the decision not to promise a store listing until one is chosen.

## What it does

- Chinese input: full pinyin, double pinyin (Xiaohe, Ziranma, Shoudao, Microsoft), Wubi 86
- Japanese input: romaji, as a scheme and as a temporary mode
- Helpcode (形码) filtering on pinyin schemes
- Optional English glosses on the right of vertical candidates, from the bundled local table
- Mixed Chinese-English input, emoji and kaomoji candidates
- Candidate learning, with the same pin / halve / linear / promote frequency modes as Windows, which can be disabled and whose learned data can be erased from the settings panel
- Voice input: cloud transcription through an endpoint you configure, or a local Whisper model that never leaves the machine

## Privacy

An input method sees every keystroke, so the boundaries are stated explicitly in [PRIVACY.md](PRIVACY.md).

Short version: the keyboard engine sends nothing. Typed text, candidates, learned words, preferences and diagnostics all stay on the Mac, and there is no telemetry, analytics or crash reporting. The two things that do touch the network are the Sparkle update check, which carries no typed text and has system profiling turned off, and voice input, which starts only when you invoke it and can run entirely locally in Whisper mode. API tokens are stored in the system Keychain.

## Building from source

```sh
brew install boost fmt spdlog nlohmann-json cmake
git submodule update --init --recursive
python3 platforms/macos/tests/create_fixture_dictionary.py /tmp/dict/msime.db
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$(brew --prefix)" \
  -DMETASEQUOIA_IME_DICTIONARY=/tmp/dict/msime.db
cmake --build build --parallel
ctest --no-tests=error --test-dir build --output-on-failure --timeout 20
```

`METASEQUOIA_IME_DICTIONARY` must point at a file literally named `msime.db`. The unit tests run against the fixture rather than the released database: they assert behaviour around composition, not dictionary content. `scripts/fetch_dictionary.py` gets the real data, verified against the digests in `product-lock.json`, and that is what a release build uses.

C++ and Objective-C++ sources are formatted with `clang-format`; run `scripts/format.sh` before opening a pull request, and `scripts/format.sh --check` to see what CI will see.

## Contributing

[CONTRIBUTING.md](https://github.com/metasequoiaime/.github/blob/main/CONTRIBUTING.md) covers the expectations. The [recruiting page](https://github.com/metasequoiaime/.github/blob/main/RECRUITING.md) lists open areas — macOS and iOS work in particular has a single maintainer today, so a second pair of hands here goes a long way.

Most issues and documentation are in Chinese. English pull requests and issues are welcome.

Suspected vulnerabilities go through the organization [SECURITY.md](https://github.com/metasequoiaime/.github/blob/main/SECURITY.md), never a public issue.

## Licence

GPL-3.0. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).
