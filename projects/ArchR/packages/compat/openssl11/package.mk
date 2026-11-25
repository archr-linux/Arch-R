# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="openssl11"
PKG_VERSION="1.1.1w"
PKG_SHA256="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
PKG_ARCH="aarch64"
PKG_LICENSE="OpenSSL"
PKG_SITE="https://www.openssl.org"
PKG_URL="https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="libcrypto.so.1.1 and libssl.so.1.1 for 64-bit PortMaster ports (Monster Hunter Tri needs libssl.so.1.1). Libraries only, in /usr/lib/compat, next to the system's OpenSSL 3."
PKG_TOOLCHAIN="manual"

# PortMaster's compat zip brings only libcrypto.so.1.1 (1.1.1c) and no
# libssl.so.1.1; this package owns both, from the same release (the
# portmaster package drops the zip's copy). archr-compat-symlinks links
# /usr/lib/libcrypto.so.1.1 at boot (consoles already have that link,
# unowned, so the package must not ship it); /usr/lib/libssl.so.1.1 is
# new, so the package ships that link and no reboot is needed.
make_target() {
  ./Configure --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared threads \
    no-tests no-zlib no-ssl3 no-weak-ssl-ciphers linux-aarch64 ${CFLAGS} ${LDFLAGS}
  make CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" build_libs
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/compat
  cp -a libcrypto.so.1.1 libssl.so.1.1 ${INSTALL}/usr/lib/compat/
  ln -sf compat/libssl.so.1.1 ${INSTALL}/usr/lib/libssl.so.1.1
}
