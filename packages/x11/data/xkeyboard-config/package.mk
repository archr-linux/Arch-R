# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="xkeyboard-config"
PKG_VERSION="2.45"
PKG_SHA256="169e075a92d957a57787c199e84e359df2931b7196c1c5b4a3d576ee6235a87c"
PKG_LICENSE="MIT"
PKG_SITE="https://www.X.org"
PKG_URL="https://www.x.org/releases/individual/data/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain util-macros"
PKG_LONGDESC="X keyboard extension data files."

configure_package() {
  if [ "${DISPLAYSERVER}" = "x11" ]; then
    PKG_DEPENDS_TARGET+=" xkbcomp"
  fi
}

pre_configure_target() {
  PKG_MESON_OPTS_TARGET="-Dcompat-rules=true"

  if [ "${DISPLAYSERVER}" = "x11" ]; then
    PKG_MESON_OPTS_TARGET+=" -Dxorg-rules-symlinks=true"
  else
    PKG_MESON_OPTS_TARGET+=" -Dxorg-rules-symlinks=false"
  fi
}
