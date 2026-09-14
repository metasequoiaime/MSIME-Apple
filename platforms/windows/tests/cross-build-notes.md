# Windows GNU build checks

```sh
bash platforms/windows/build-cross.sh x64
MSIME_WINDOWS_DEPS="$PWD/target/windows-native-deps/x64/x64-mingw-static" \
  CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc \
  cargo check -p msime-desktop --target x86_64-pc-windows-gnu --locked
```

The script uses the repository's pinned vcpkg manifest, builds the Rust host
DLL and dictionary replay executable, and compiles/links the native Server,
TSF DLL, supported UI demos and tests. It explicitly excludes the optional
SDK C++/WinRT handwriting demo (`MSIMEUI_BUILD_HANDWRITING_DEMO=OFF`); normal
CMake builds keep that option enabled. It does not execute Windows binaries,
register TSF, exercise audio hardware or bundle MinGW runtime DLLs.

The TSF dynamic thread-local strings have a single source definition while
retaining per-thread storage. MinGW gets the two property GUID definitions
absent from its UUID archive; values match Microsoft's windows-sys 0.61.2
bindings. MSVC continues to use the SDK UUID library. Unicode startup flags
are applied to the UI demos, and Server Unicode macros apply to both compilers.

The candidate initialization regression also runs on a host compiler with
the manifest's header-only JSON dependency:

```sh
c++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -Iplatforms/windows -Icrates/host-api/include -Ivendor/MSIME-Engine/contracts \
  -Itarget/windows-native-deps/x64/x64-mingw-static/include \
  platforms/windows/tests/candidate_initialization.cpp \
  platforms/windows/ChineseTextConversion.cpp -o target/candidate-initialization
./target/candidate-initialization
```

All fixtures use synthetic data. Local cross-compilation is not native runtime
verification or evidence of complete Windows feature parity.
