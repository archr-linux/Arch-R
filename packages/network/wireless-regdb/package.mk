# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="wireless-regdb"
PKG_VERSION="2026.05.30"
PKG_SHA256="8a27bfc081bafed8c24dd70fab0d96f098e5a0bfcd08d3da672595f225ab8993"
PKG_LICENSE="ISC"
PKG_SITE="https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb"
PKG_URL="https://www.kernel.org/pub/software/network/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_LONGDESC="wireless-regdb is a regulatory database"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  FW_TARGET_DIR=${INSTALL}/$(get_full_firmware_dir)

  mkdir -p ${FW_TARGET_DIR}
    cp ${PKG_BUILD}/regulatory.db ${PKG_BUILD}/regulatory.db.p7s ${FW_TARGET_DIR}
}

makeinstall_init() {
  # cfg80211 is builtin and requests regulatory.db before kernel-overlays-setup
  # populates /run/kernel-overlays/firmware; a failed load is cached forever
  # (regdb = ERR_PTR in net/wireless/reg.c), leaving the world domain active
  # for the whole session. Ship the db in the initramfs so the very first
  # request succeeds.
  mkdir -p ${INSTALL}/usr/lib/firmware
    cp ${PKG_BUILD}/regulatory.db ${PKG_BUILD}/regulatory.db.p7s ${INSTALL}/usr/lib/firmware
}
