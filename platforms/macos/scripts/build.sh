#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h:h:h}
# Take the released database rather than rebuilding it, so a local build ships what a release ships. Dictionary sources and the public build_profile.py entry point live in MSIME-Engine.
python3 "$project_root/scripts/fetch_dictionary.py"
cmake -S "$project_root" -B "$project_root/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$(brew --prefix)"
cmake --build "$project_root/build" --parallel
ctest --test-dir "$project_root/build" --output-on-failure --timeout 20
codesign --verify --deep --strict --verbose=2 "$project_root/build/MetasequoiaIME.app"
