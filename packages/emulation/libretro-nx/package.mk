# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-nx"
PKG_VERSION="9adc032a5f6aa913d71d22042bb72cb11cf0f4a2"
PKG_SHA256="bc065a4f82f3644888f01fcaca482e1ead03055df03d8453bd8efed62c176d26"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/nxengine-libretro"
PKG_URL="https://github.com/libretro/nxengine-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Port of NxEngine to libretro - Cave Story game engine clone"
PKG_TOOLCHAIN="make"

PKG_LIBNAME="nxengine_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="NX_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake

  mkdir -p ${SYSROOT_PREFIX}/usr/share/retroarch/system/nxengine
  cp -vr datafiles/* ${SYSROOT_PREFIX}/usr/share/retroarch/system/nxengine
}
