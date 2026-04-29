# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="w_scan"
PKG_VERSION="20210218"
PKG_SHA256="75d7447ebeddfb9ce251f32a93f23190ed46dca44f5b701f2af11e1787b9eb08"
PKG_LICENSE="GPL"
PKG_SITE="https://www.gen2vdr.de/wirbel/w_scan_cpp/index2.html"
PKG_URL="https://www.gen2vdr.de/wirbel/w_scan_cpp/w_scan-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A channel scan tool which generates ATSC, DVB-C, DVB-S/S2 and DVB-T channels.conf files."
PKG_TOOLCHAIN="autotools"
PKG_BUILD_FLAGS="-sysroot -cfg-libs"
