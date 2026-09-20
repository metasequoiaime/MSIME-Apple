# Cross-build the Windows targets for an architecture this host has no working
# toolchain for.
#
# x86 is the reason this exists. The 32-bit TSF DLL is loaded into every 32-bit
# host process, and it had never been linked: `build-cross.sh x86` refuses when
# the i686 MinGW uses SJLJ exceptions, because Rust's i686-pc-windows-gnu needs
# DWARF unwinding, and the i686 toolchain Homebrew ships is SJLJ. That is a
# property of one machine, not of the architecture - Debian's i686 MinGW is
# built `--disable-sjlj-exceptions --with-dwarf2`, so the same build works here.
#
# linux/amd64 because vcpkg's host tools are built for the container's own
# architecture; on an arm64 host Docker emulates, which is slow but correct.
FROM debian:trixie-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
    g++-mingw-w64-i686 g++-mingw-w64-x86-64 \
    build-essential cmake ninja-build pkg-config \
    curl ca-certificates git zip unzip tar python3 \
 && rm -rf /var/lib/apt/lists/*
# Debian ships win32 and posix thread variants side by side and leaves the
# unsuffixed name pointing at win32, whose C++ standard library has no
# std::thread. The project uses it, so select posix explicitly.
RUN update-alternatives --set i686-w64-mingw32-gcc /usr/bin/i686-w64-mingw32-gcc-posix \
 && update-alternatives --set i686-w64-mingw32-g++ /usr/bin/i686-w64-mingw32-g++-posix \
 && update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix \
 && update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix
# Windows filesystems are case-insensitive and so is macOS's by default, so
# `#include <Windows.h>` resolves there against the toolchain's lowercase
# windows.h. Linux is case-sensitive and it does not. That is a property of
# this container rather than a defect in the sources, so the container supplies
# the missing spellings: an initial-capital alias for every MinGW header that
# does not already have one.
RUN for dir in /usr/share/mingw-w64/include /usr/i686-w64-mingw32/include /usr/x86_64-w64-mingw32/include; do \
      [ -d "$dir" ] || continue; \
      for header in "$dir"/[a-z]*.h; do \
        [ -e "$header" ] || continue; \
        name=$(basename "$header"); \
        capital=$(printf '%s' "$name" | cut -c1 | tr 'a-z' 'A-Z')$(printf '%s' "$name" | cut -c2-); \
        [ -e "$dir/$capital" ] || ln -s "$name" "$dir/$capital"; \
      done; \
    done

RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH=/root/.cargo/bin:$PATH
RUN rustup target add i686-pc-windows-gnu x86_64-pc-windows-gnu
ENV VCPKG_DISABLE_METRICS=1
