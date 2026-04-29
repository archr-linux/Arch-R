# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2023-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libretro-bsnes-hd"
PKG_VERSION="0bb7b8645e22ea2476cabd58f32e987b14686601"
PKG_SHA256="f7c498b927daca8c7d69124369670e749a4e13422411cf7136da695e60da3dc7"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/DerKoun/bsnes-hd"
PKG_URL="https://github.com/DerKoun/bsnes-hd/archive/${PKG_VERSION}.tar.gz"
PKG_BRANCH="master"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Fork of bsnes that adds HD video features."
PKG_TOOLCHAIN="make"

make_target() {
  make -C bsnes -f GNUmakefile target="libretro" compiler="${CXX}" CXXFLAGS="${CXXFLAGS}" platform=linux local=false binary=library
}

PKG_LIBNAME="bsnes_hd_beta_libretro.so"
PKG_LIBPATH="bsnes/out/${PKG_LIBNAME}"
PKG_LIBVAR="BSNES-HD_LIB"

makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}
  cp ${PKG_LIBPATH} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME}
  echo "set(${PKG_LIBVAR} ${SYSROOT_PREFIX}/usr/lib/${PKG_LIBNAME})" >${SYSROOT_PREFIX}/usr/lib/cmake/${PKG_NAME}/${PKG_NAME}-config.cmake
}
