FROM rust:1.97.1-bookworm@sha256:0e2bcaef56d041a486784e54104a81aebe0da44bd03019bd70bc0401e42e4a97
RUN apt-get update && apt-get install -y --no-install-recommends cmake ninja-build libboost-dev libfmt-dev libspdlog-dev libsqlite3-dev libicu-dev libibus-1.0-dev nlohmann-json3-dev dbus ibus ibus-gtk3 gir1.2-gtk-3.0 xvfb xauth xdotool && rm -rf /var/lib/apt/lists/*
WORKDIR /source
