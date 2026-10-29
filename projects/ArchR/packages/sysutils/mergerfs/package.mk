# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="mergerfs"
PKG_VERSION="2.42.0"
PKG_SHA256="546d6eed694d48ef13e058a46c6fb3da34dc9dfc48ee51af6487f353787780bd"
PKG_LICENSE="ISC"
PKG_SITE="https://github.com/trapexit/mergerfs"
PKG_URL="${PKG_SITE}/releases/download/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Union filesystem: both microSD cards' ROM folders seen as one (unified storage)."
PKG_TOOLCHAIN="make"

# libfuse is vendored and linked statically; the kernel has FUSE built in.
# Run as root by automount, so no fusermount/mount.mergerfs helper is needed.
PKG_MAKE_OPTS_TARGET="NDEBUG=1 USE_XATTR=1"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/build/mergerfs ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/mergerfs
}
