# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="dtv-scan-tables"
PKG_VERSION="2025-06-06-caca23fb5466"
PKG_SHA256="415894e601a53d827ec85e333b7b0afb0bf2fc7abf98df606a0d120353d408f3"
PKG_LICENSE="GPL"
PKG_SITE="https://git.linuxtv.org/dtv-scan-tables.git"
PKG_URL="https://linuxtv.org/downloads/dtv-scan-tables/dtv-scan-tables-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Digital TV scan tables."
PKG_TOOLCHAIN="manual"
PKG_BUILD_FLAGS="-sysroot"

makeinstall_target() {
  make -C share/dvb install DATADIR=${INSTALL}/usr/share
}
