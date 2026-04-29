# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libXxf86vm"
PKG_VERSION="1.1.6"
PKG_SHA256="96af414c73ce1d5449ad04be7f9f27fa8330f844b6dda843ef22e3e1befb3ee3"
PKG_LICENSE="OSS"
PKG_SITE="http://www.X.org"
PKG_URL="http://xorg.freedesktop.org/archive/individual/lib/${PKG_NAME}-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain util-macros libX11 libXext"
PKG_LONGDESC="The libxxf86vm provides an interface to the server extension XFree86-VidModeExtension."
PKG_BUILD_FLAGS="+pic"

PKG_CONFIGURE_OPTS_TARGET="--enable-static --disable-shared --enable-malloc0returnsnull"
