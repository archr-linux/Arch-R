# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/network/iwd/package.mk

PKG_VERSION="3.12"
PKG_SHA256="d89a5e45c7180170e19be828f9e944a768c593758094fc57a358d0e7c4cb1a49"
PKG_URL="https://www.kernel.org/pub/linux/network/wireless/iwd-${PKG_VERSION}.tar.xz"

pre_configure_target() {
  export LIBS="-lncurses -ltinfo"
}

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/lib/systemd/system

  mkdir -p ${INSTALL}/etc/iwd
    cp -P ${PKG_DIR}/sources/main.conf ${INSTALL}/etc/iwd

  mkdir -p ${INSTALL}/usr/bin
    cp -P ${PKG_DIR}/scripts/iwd_get-networks ${INSTALL}/usr/bin

  # FHS bridge: /var/lib/iwd is the Arch-standard state dir. tmpfiles
  # z_03_iwd.conf creates the backing /storage/.cache/iwd so the
  # symlinked target is writable on first boot.
  mkdir -p ${INSTALL}/var/lib
  ln -sf /storage/.cache/iwd ${INSTALL}/var/lib/iwd
}
