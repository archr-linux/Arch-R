# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2017-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="squashfs-tools"
PKG_VERSION="4.7"
PKG_SHA256="f1605ef720aa0b23939a49ef4491f6e734333ccc4bda4324d330da647e105328"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/plougher/squashfs-tools"
PKG_URL="https://github.com/plougher/squashfs-tools/releases/download/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="ccache:host zlib:host lzo:host zstd:host"
PKG_DEPENDS_TARGET="toolchain zlib lzo zstd xz"
PKG_NEED_UNPACK="$(get_pkg_directory zlib) $(get_pkg_directory lzo) $(get_pkg_directory zstd)"
PKG_LONGDESC="Tools for squashfs, a highly compressed read-only filesystem for Linux."
PKG_TOOLCHAIN="manual"

make_host() {
  make -C squashfs-tools \
          mksquashfs \
          XZ_SUPPORT=0 \
          LZO_SUPPORT=1 \
          LZ4_SUPPORT=0 \
          ZSTD_SUPPORT=1 \
          XATTR_SUPPORT=0 \
          XATTR_DEFAULT=0 \
          INCLUDEDIR="-I. -I${TOOLCHAIN}/include"
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp squashfs-tools/mksquashfs ${TOOLCHAIN}/bin
}

make_target() {
  make -C squashfs-tools clean
  make -C squashfs-tools \
          mksquashfs unsquashfs \
          XZ_SUPPORT=1 \
          LZO_SUPPORT=1 \
          LZ4_SUPPORT=0 \
          ZSTD_SUPPORT=1 \
          XATTR_SUPPORT=0 \
          XATTR_DEFAULT=0
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp squashfs-tools/mksquashfs ${INSTALL}/usr/bin/
  cp squashfs-tools/unsquashfs ${INSTALL}/usr/bin/
}
