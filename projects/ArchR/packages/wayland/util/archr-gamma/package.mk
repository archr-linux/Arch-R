# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="archr-gamma"
PKG_VERSION="1.0"
PKG_REV="2"
PKG_LICENSE="GPL"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain wayland wayland:host"
PKG_LONGDESC="Holds the panel's gamma curve and colour temperature through sway (wlr-gamma-control), from system.cfg."
PKG_TOOLCHAIN="manual"

make_target() {
  local proto=wlr-gamma-control-unstable-v1
  ${TOOLCHAIN}/bin/wayland-scanner client-header ${PKG_DIR}/sources/${proto}.xml ${proto}-client-protocol.h
  ${TOOLCHAIN}/bin/wayland-scanner private-code ${PKG_DIR}/sources/${proto}.xml ${proto}-protocol.c
  ${CC} ${CFLAGS} -I. -o archr-gamma ${PKG_DIR}/sources/archr-gamma.c ${proto}-protocol.c ${LDFLAGS} -lwayland-client -lm
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin ${INSTALL}/usr/lib/systemd/system
  cp archr-gamma ${INSTALL}/usr/bin/
  cp ${PKG_DIR}/system.d/archr-gamma.service ${INSTALL}/usr/lib/systemd/system/
}
