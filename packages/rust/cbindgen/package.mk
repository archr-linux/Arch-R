# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="cbindgen"
PKG_VERSION="0.29.0"
PKG_SHA256="6697f449d4a15d814d991249a611af961c97e36d9344c7ced6df35c5c25b40cc"
PKG_LICENSE="MPL-2.0"
PKG_SITE="https://github.com/mozilla/bindgen"
PKG_URL="https://github.com/mozilla/cbindgen/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="cargo:host"
PKG_LONGDESC="A project for generating C bindings from Rust code"
PKG_TOOLCHAIN="manual"

configure_host() {
  cd ${PKG_BUILD}
}

make_host() {
  cd ${PKG_BUILD}

  cargo build -v --target ${RUST_HOST} --release
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp -a ${PKG_BUILD}/.${RUST_HOST}/target/${RUST_HOST}/release/cbindgen ${TOOLCHAIN}/bin/
}
