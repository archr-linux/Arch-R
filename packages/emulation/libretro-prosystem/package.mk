# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-prosystem"
PKG_VERSION="acae250da8d98b8b9707cd499e2a0bf6d8500652"
PKG_SHA256="5a376c6621678daff86977de12b1421f1599602683a8d7228f75281ab4274229"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/libretro/prosystem-libretro"
PKG_URL="https://github.com/libretro/prosystem-libretro/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Port of ProSystem to libretro."
PKG_TOOLCHAIN="make"

PKG_LIBNAME="prosystem_libretro.so"
PKG_LIBPATH="${PKG_LIBNAME}"
PKG_LIBVAR="PROSYSTEM_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
