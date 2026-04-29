# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libhdhomerun"
PKG_VERSION="20231214"
PKG_SHA256="552a102e8aa2abcc416090dec2f6f80da59f97f91f57968e9e9d7b3dc005dbaf"
PKG_LICENSE="LGPL"
PKG_SITE="http://www.silicondust.com"
PKG_URL="https://download.silicondust.com/hdhomerun/libhdhomerun_${PKG_VERSION}.tgz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="The library provides functionality to setup the HDHomeRun."

PKG_MAKE_OPTS_TARGET="CROSS_COMPILE=${TARGET_PREFIX}"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/include/hdhomerun
    cp *.h ${SYSROOT_PREFIX}/usr/include/hdhomerun

  mkdir -p ${SYSROOT_PREFIX}/usr/lib
    cp libhdhomerun.a ${SYSROOT_PREFIX}/usr/lib
}
