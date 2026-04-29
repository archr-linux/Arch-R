# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="exfatprogs"
PKG_VERSION="1.2.9"
PKG_SHA256="d9a42197c6ff9e6a8e923789413008e317415cf7a4ab85c486c5ffcaf49ca175"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/exfatprogs/exfatprogs"
PKG_URL="https://github.com/exfatprogs/exfatprogs/releases/download/${PKG_VERSION}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="userspace utilities that contain all of the standard utilities for creating and fixing and debugging exfat filesystems."
PKG_TOOLCHAIN="autotools"

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/share
}
