# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="lib32-openssl11"
PKG_VERSION="1.1.1w"
PKG_SHA256="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
PKG_LICENSE="OpenSSL"
PKG_SITE="https://www.openssl.org"
PKG_URL="https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libcrypto.so.1.1 and libssl.so.1.1 for 32-bit PortMaster ports (gmloader's libzip.so.5 needs them; the 64-bit pair comes from PortMaster's compat zip). Built for arm, installed to /usr/lib32 by the aarch64 package."
PKG_TOOLCHAIN="manual"

# arm: build the libraries, kept out of the arm image's /usr/lib (lib32
# copies that whole tree; this package owns the two files). aarch64: ship
# the arm build's two libraries in /usr/lib32.
make_target() {
  [ "${TARGET_ARCH}" = arm ] || return 0
  ./Configure --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared threads \
    no-tests no-zlib no-ssl3 no-weak-ssl-ciphers linux-armv4 ${CFLAGS} ${LDFLAGS}
  make CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" build_libs
}

makeinstall_target() {
  case ${TARGET_ARCH} in
    arm)
      mkdir -p ${INSTALL}/usr/lib-openssl11
      cp -a libcrypto.so.1.1 libssl.so.1.1 ${INSTALL}/usr/lib-openssl11/
      ;;
    aarch64)
      arm="${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/${PKG_NAME}-${PKG_VERSION}"
      [ -f "${arm}/usr/lib-openssl11/libcrypto.so.1.1" ] || die "${PKG_NAME}: build it for ARCH=arm first"
      mkdir -p ${INSTALL}/usr/lib32
      cp -a ${arm}/usr/lib-openssl11/libcrypto.so.1.1 ${arm}/usr/lib-openssl11/libssl.so.1.1 ${INSTALL}/usr/lib32/
      ;;
  esac
}
