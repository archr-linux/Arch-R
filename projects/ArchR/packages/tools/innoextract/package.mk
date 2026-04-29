# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="innoextract"
PKG_VERSION="1.9"
PKG_SHA256="6344a69fc1ed847d4ed3e272e0da5998948c6b828cb7af39c6321aba6cf88126"
PKG_LICENSE="Zlib"
PKG_SITE="https://constexpr.org/innoextract/"
PKG_URL="https://github.com/dscharrer/innoextract/releases/download/${PKG_VERSION}/innoextract-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain boost xz zlib"
PKG_LONGDESC="Tool for extracting Inno Setup installers (GOG games)."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_BUILD_TYPE=Release \
                       -DUSE_LZMA=ON \
                       -DUSE_STATIC_LIBS=ON"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a innoextract ${INSTALL}/usr/bin/
}
