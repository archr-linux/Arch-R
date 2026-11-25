# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="librknnrt"
PKG_VERSION="2.5.0"
PKG_REV="1"
PKG_ARCH="aarch64"
# Rockchip's closed RKNN runtime, unmodified, from the rknn-toolkit2 release
# (the same file and checksum dArkOS for the RG52 Mini ships). It talks to
# the rknpu kernel driver. Rockchip's license (installed beside it) allows
# its use with applications for Rockchip's chips and asks that its notices
# be kept; only the RK3562 image installs it.
PKG_LICENSE="nonfree"
PKG_SITE="https://github.com/airockchip/rknn-toolkit2"
PKG_URL="https://raw.githubusercontent.com/airockchip/rknn-toolkit2/v${PKG_VERSION}/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so"
PKG_SOURCE_NAME="librknnrt-${PKG_VERSION}-aarch64.so"
PKG_SHA256="4b6cc575bedf8952b13db4b1190fa3b3d2ac213f00be774ff6ccd19d651970c0"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Rockchip RKNN runtime for the NPU"
PKG_TOOLCHAIN="manual"
# a vendor binary: keep it byte for byte as published
PKG_BUILD_FLAGS="-strip"

unpack() {
  mkdir -p ${PKG_BUILD}
  cp ${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME} ${PKG_BUILD}/librknnrt.so
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib ${INSTALL}/usr/share/licenses/${PKG_NAME}
  install -m 0644 ${PKG_BUILD}/librknnrt.so ${INSTALL}/usr/lib/librknnrt.so
  install -m 0644 ${PKG_DIR}/LICENSE ${INSTALL}/usr/share/licenses/${PKG_NAME}/LICENSE
}
