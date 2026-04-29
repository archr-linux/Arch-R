# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

. ${ROOT}/packages/x11/lib/libxcb/package.mk

PKG_DEPENDS_HOST="toolchain:host util-macros:host Python3:host xcb-proto:host libpthread-stubs:host libXau:host"

post_configure_target() {
  # Disable libtool relink during install - fails in cross-compilation
  # because the linker rejects host /usr/lib as unsafe
  for lt in ${PKG_BUILD}/.*/libtool; do
    [ -f "$lt" ] && sed -i 's|need_relink=yes|need_relink=no|g' "$lt"
  done
}
