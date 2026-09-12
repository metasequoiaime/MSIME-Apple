FROM rust:1.97.1-bookworm@sha256:0e2bcaef56d041a486784e54104a81aebe0da44bd03019bd70bc0401e42e4a97
RUN apt-get update && apt-get install -y --no-install-recommends cmake ninja-build libboost-dev libfmt-dev libspdlog-dev libsqlite3-dev libicu-dev libibus-1.0-dev libxkbcommon-dev nlohmann-json3-dev dbus ibus ibus-gtk3 gir1.2-gtk-3.0 xvfb xauth xdotool x11-xkb-utils python3-pyqt5 python3-pyqt6 qtwayland5 qt6-wayland sway libwayland-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /source

COPY virtual-keyboard-unstable-v1.xml wayland_keyboard.c /tmp/msime-wayland-driver/
RUN cd /tmp/msime-wayland-driver && wayland-scanner client-header virtual-keyboard-unstable-v1.xml virtual-keyboard-client.h && wayland-scanner private-code virtual-keyboard-unstable-v1.xml virtual-keyboard-protocol.c && cc -Wall -Wextra -Werror wayland_keyboard.c virtual-keyboard-protocol.c $(pkg-config --cflags --libs wayland-client) -o /usr/local/bin/msime-test-wayland-keyboard && rm -rf /tmp/msime-wayland-driver
