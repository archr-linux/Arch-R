# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="libnl"
PKG_VERSION="3.11.0"
PKG_SHA256="2a56e1edefa3e68a7c00879496736fdbf62fc94ed3232c0baba127ecfa76874d"
PKG_LICENSE="LGPL"
PKG_SITE="https://github.com/thom311/libnl"
PKG_URL="https://github.com/thom311/libnl/releases/download/libnl${PKG_VERSION//./_}/libnl-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A library for applications dealing with netlink socket."
PKG_BUILD_FLAGS="+pic"

PKG_CONFIGURE_OPTS_TARGET="--enable-static \
                           --disable-shared \
                           --disable-cli"
