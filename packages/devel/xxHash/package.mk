# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2024-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="xxHash"
PKG_VERSION="0.8.3"
PKG_SHA256="aae608dfe8213dfd05d909a57718ef82f30722c392344583d3f39050c7f29a80"
PKG_LICENSE="BSD-2-Clause"
PKG_SITE="https://xxhash.com"
PKG_URL="https://github.com/Cyan4973/xxHash/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="make:host"
PKG_LONGDESC="Extremely fast non-cryptographic hash algorithm"
PKG_BUILD_FLAGS="+local-cc"

pre_configure_host() {
  export prefix=${TOOLCHAIN}
}
