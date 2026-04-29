# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2012 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="dvblast"
PKG_VERSION="405917e77f0f08b4c130ae4611c3ca6cf82119c1"
PKG_SHA256="9aea0107b5c91a76cd7a8b9038029e7af4f5a285ef5cd6b70b259dee17986af2"
PKG_LICENSE="GPL"
PKG_SITE="https://www.videolan.org/projects/dvblast.html"
PKG_URL="http://repo.or.cz/dvblast.git/snapshot/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain bitstream libev"
PKG_LONGDESC="DVBlast is a simple and powerful MPEG-2/TS demux and streaming application"
PKG_BUILD_FLAGS="-sysroot"

pre_configure_target() {
  export LDFLAGS="${LDFLAGS} -lm"
  export PREFIX="/usr"
}
