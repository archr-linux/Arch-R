# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="lib32-libzip"
PKG_VERSION="1.11.1"
PKG_LICENSE="BSD"
PKG_SITE="https://libzip.org"
PKG_URL="https://libzip.org/download/libzip-${PKG_VERSION}.tar.xz"
PKG_SOURCE_DIR="libzip-${PKG_VERSION}"
PKG_DEPENDS_TARGET="toolchain zlib openssl bzip2 xz zstd"
PKG_LONGDESC="libzip.so.5 for 32-bit PortMaster ports: gmloader (32-bit GameMaker) loads it from the system when the port does not bring its own. Built for arm (OpenSSL, no GnuTLS: the 32-bit tree has none), installed to /usr/lib32 by the aarch64 package."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DBUILD_SHARED_LIBS=ON \
                       -DENABLE_GNUTLS=OFF \
                       -DENABLE_MBEDTLS=OFF \
                       -DENABLE_OPENSSL=ON \
                       -DBUILD_TOOLS=OFF \
                       -DBUILD_REGRESS=OFF \
                       -DBUILD_OSSFUZZ=OFF \
                       -DBUILD_EXAMPLES=OFF \
                       -DBUILD_DOC=OFF"

# arm: kept out of the arm image's /usr/lib (lib32 copies that whole tree;
# this package owns the files). aarch64: ship the arm build in /usr/lib32.
makeinstall_target() {
  case ${TARGET_ARCH} in
    arm)
      mkdir -p ${INSTALL}/usr/lib-libzip32
      cp -a lib/libzip.so.5* ${INSTALL}/usr/lib-libzip32/
      ;;
    aarch64)
      arm="${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/${PKG_NAME}-${PKG_VERSION}"
      [ -f "${arm}/usr/lib-libzip32/libzip.so.5" ] || die "${PKG_NAME}: build it for ARCH=arm first"
      mkdir -p ${INSTALL}/usr/lib32
      cp -a ${arm}/usr/lib-libzip32/libzip.so.5* ${INSTALL}/usr/lib32/
      ;;
  esac
}
