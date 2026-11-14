# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="physfs"
PKG_VERSION="3.2.0"
PKG_LICENSE="zlib"
PKG_SITE="https://icculus.org/physfs/"
PKG_URL="https://github.com/icculus/physfs/archive/refs/tags/release-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libphysfs.so.1: PortMaster's Solarus runtime (Yarntown, Ocean's Heart and every other Solarus game) loads it from the system."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DPHYSFS_BUILD_STATIC=OFF \
                       -DPHYSFS_BUILD_SHARED=ON \
                       -DPHYSFS_BUILD_TEST=OFF \
                       -DPHYSFS_BUILD_DOCS=OFF"

# Only the library: nothing on the console builds against it.
post_makeinstall_target() {
  rm -r ${INSTALL}/usr/include
  rm -r ${INSTALL}/usr/lib/pkgconfig ${INSTALL}/usr/lib/cmake 2>/dev/null || :
}
