# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="configtools"
PKG_VERSION="system"
PKG_LICENSE="GPL"
PKG_SITE="https://www.gnu.org/software/config/"
PKG_URL=""
PKG_DEPENDS_HOST=""
PKG_LONGDESC="GNU config.guess and config.sub from system automake"
PKG_TOOLCHAIN="manual"

unpack() {
  mkdir -p ${PKG_BUILD}
  # Copy config.guess and config.sub from system automake
  local automake_share=$(ls -d /usr/share/automake-* 2>/dev/null | head -1)
  if [ -n "${automake_share}" ]; then
    cp ${automake_share}/config.guess ${PKG_BUILD}/
    cp ${automake_share}/config.sub ${PKG_BUILD}/
  else
    # Fallback: use the ones from /usr/share/libtool
    cp /usr/share/libtool/build-aux/config.guess ${PKG_BUILD}/ 2>/dev/null || true
    cp /usr/share/libtool/build-aux/config.sub ${PKG_BUILD}/ 2>/dev/null || true
  fi
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/configtools
  cp config.* ${TOOLCHAIN}/configtools
}
