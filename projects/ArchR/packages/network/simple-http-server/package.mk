# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2023-present NeoTheFox (https://github.com/NeoTheFox)
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="simple-http-server"
PKG_VERSION="0.8.0"
PKG_SHA256="b60965e0b0cd652bcb734185e6d8395cd4c1326305b190cba6ba0d7819f38af2"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/TheWaWaR/simple-http-server"
PKG_URL="${PKG_SITE}/archive/refs/tags/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain cargo:host rust:host"
PKG_LONGDESC="Simple http server in Rust"
# Built from source (it was the upstream release binary) to carry
# patches/001: a wrong user or password answered 401 without
# WWW-Authenticate, and the browser never asked again (Arch-R#57).
PKG_TOOLCHAIN="manual"

make_target() {
  cargo build --locked --release --target "${TARGET_NAME}" \
    --manifest-path "${PKG_BUILD}/Cargo.toml"
}

makeinstall_target() {
  install -Dm755 "${PKG_BUILD}/.${TARGET_NAME}/target/${TARGET_NAME}/release/simple-http-server" \
    "${INSTALL}/usr/bin/simple-http-server"
  install -Dm644 "${PKG_BUILD}/LICENSE" "${INSTALL}/usr/share/licenses/simple-http-server/LICENSE"

  mkdir -p ${INSTALL}/usr/lib/systemd/system
  install -Dm644 ${PKG_DIR}/system.d/simple-http-server.service ${INSTALL}/usr/lib/systemd/system
}
