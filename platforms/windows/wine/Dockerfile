# Runs the cross-built Windows test executables without a Windows machine.
#
# Wine 10 rather than whatever is oldest: the Rust host library pulls in
# bcryptprimitives.dll, which Wine 8 does not implement, and four suites fail
# to load at all without it. linux/amd64 because the binaries are x86_64 PE;
# on an arm64 host Docker emulates, which is slow but correct.
FROM debian:trixie-slim
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends wine \
 && rm -rf /var/lib/apt/lists/*
ENV WINEDEBUG=-all
ENV WINEPREFIX=/wine
RUN wineboot --init 2>/dev/null; true
