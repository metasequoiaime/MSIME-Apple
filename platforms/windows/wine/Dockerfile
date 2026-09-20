# Runs the cross-built Windows test executables without a Windows machine.
#
# Wine 10 rather than whatever is oldest: the Rust host library pulls in
# bcryptprimitives.dll, which Wine 8 does not implement, and four suites fail
# to load at all without it. linux/amd64 because the binaries are x86_64 PE;
# on an arm64 host Docker emulates, which is slow but correct.
#
# Xvfb because two suites create real windows. Without a display Wine falls back
# to a null driver, window creation fails, and those suites report an
# environment failure that is really a missing X server - which this image can
# supply, unlike a real monitor.
FROM debian:trixie-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends wine xvfb xauth \
 && rm -rf /var/lib/apt/lists/*
ENV WINEDEBUG=-all
ENV WINEPREFIX=/wine
RUN wineboot --init 2>/dev/null; true
