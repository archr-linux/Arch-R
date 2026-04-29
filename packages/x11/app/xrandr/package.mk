# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2020-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="xrandr"
PKG_VERSION="1.5.3"
PKG_SHA256="f8dd7566adb74147fab9964680b6bbadee87cf406a7fcff51718a5e6949b841c"
PKG_LICENSE="OSS"
PKG_SITE="https://www.X.org"
PKG_URL="https://xorg.freedesktop.org/archive/individual/app/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain util-macros libXrandr"
PKG_LONGDESC="Xrandr is a primitive command line interface to the RandR extension and used to set the screen size, orientation and/or reflection."

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin/xkeystone
}
