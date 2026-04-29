# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="espeak-ng"
PKG_VERSION="348599e02bf0db105ac6fd07693e4047f614a58e"
PKG_SHA256="f12884158f1e6c3727bcc340f2459a0a5481f8e02f7c35dbd69dae936f064d1c"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/espeak-ng/espeak-ng"
PKG_URL="https://github.com/espeak-ng/espeak-ng/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="gcc:host"
PKG_DEPENDS_TARGET="toolchain espeak-ng:host"
PKG_LONGDESC="eSpeak NG is an open source speech synthesizer that supports more than a hundred languages and accents"
PKG_BUILD_FLAGS="+pic"

PKG_CMAKE_OPTS_HOST="-DBUILD_SHARED_LIBS=OFF \
                     -DCOMPILE_INTONATIONS=OFF \
                     -DENABLE_TESTS=OFF"

PKG_CMAKE_OPTS_TARGET="-DBUILD_SHARED_LIBS=ON \
                       -DCOMPILE_INTONATIONS=ON \
                       -DENABLE_TESTS=OFF \
                       -DNativeBuild_DIR=${TOOLCHAIN}/bin"

post_makeinstall_target() {
  safe_remove ${INSTALL}/usr/share/vim

  # add symlink for backwards compatibility with old programs
  ln -sf espeak-ng ${INSTALL}/usr/bin/espeak
}
