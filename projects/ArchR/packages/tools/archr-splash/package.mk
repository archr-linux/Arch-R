# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="archr-splash"
PKG_VERSION="3527c70c21d4552c4049990ca6057cc223cf8d33"
PKG_LICENSE="GPL"
PKG_SITE="https://arch-r.io"
PKG_URL="https://github.com/archr-linux/${PKG_NAME}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_INIT="toolchain"
PKG_LONGDESC="ArchR splash screen application"

post_unpack() {
  # Fix binary name: rocknix-splash -> archr-splash
  sed -i 's|TARGET=rocknix-splash|TARGET=archr-splash|' ${PKG_BUILD}/Makefile
}
