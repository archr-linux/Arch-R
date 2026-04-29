# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="ap6611s"
PKG_VERSION=""
PKG_LICENSE="GPLv2"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain systemd"
PKG_LONGDESC="Bluetooth service for ap6611s chip"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/bin/brcm_patchram_plus_rk3399 ${INSTALL}/usr/bin
  chmod +x ${INSTALL}/usr/bin/brcm_patchram_plus_rk3399
}
