# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="librknnrt"
PKG_VERSION="2.5.0"
PKG_REV="1"
PKG_ARCH="aarch64 arm"
# Rockchip's closed RKNN runtime, unmodified, from the rknn-toolkit2 release
# (the same file and checksum dArkOS for the RG52 Mini ships). It talks to
# the rknpu kernel driver. Rockchip's license (installed beside it) allows
# its use with applications for Rockchip's chips and asks that its notices
# be kept; only the RK3562 image installs it.
PKG_LICENSE="nonfree"
PKG_SITE="https://github.com/airockchip/rknn-toolkit2"
case ${TARGET_ARCH} in
  arm)
    RKNN_ARCH="armhf"
    PKG_SHA256="267193f5f32f01f6e9137072c67ca737d57528257f1a63ce4d65e3698369ffa3"
    ;;
  *)
    RKNN_ARCH="aarch64"
    PKG_SHA256="4b6cc575bedf8952b13db4b1190fa3b3d2ac213f00be774ff6ccd19d651970c0"
    ;;
esac
PKG_URL="https://raw.githubusercontent.com/airockchip/rknn-toolkit2/v${PKG_VERSION}/rknpu2/runtime/Linux/librknn_api/${RKNN_ARCH}/librknnrt.so"
PKG_SOURCE_NAME="librknnrt-${PKG_VERSION}-${RKNN_ARCH}.so"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Rockchip RKNN runtime for the NPU"
PKG_TOOLCHAIN="manual"
# a vendor binary: keep it byte for byte as published
PKG_BUILD_FLAGS="-strip"

unpack() {
  mkdir -p ${PKG_BUILD}
  cp ${SOURCES}/${PKG_NAME}/${PKG_SOURCE_NAME} ${PKG_BUILD}/librknnrt.so
}

# arm: the armhf runtime, kept out of the arm image's /usr/lib (lib32
# copies that whole tree; this package owns the file). aarch64: both, the
# armhf one in /usr/lib32 for the 32-bit RetroArch (pcsx_rearmed32).
makeinstall_target() {
  case ${TARGET_ARCH} in
    arm)
      mkdir -p ${INSTALL}/usr/lib-rknnrt32
      install -m 0644 ${PKG_BUILD}/librknnrt.so ${INSTALL}/usr/lib-rknnrt32/librknnrt.so
      ;;
    aarch64)
      mkdir -p ${INSTALL}/usr/lib ${INSTALL}/usr/share/licenses/${PKG_NAME}
      install -m 0644 ${PKG_BUILD}/librknnrt.so ${INSTALL}/usr/lib/librknnrt.so
      install -m 0644 ${PKG_DIR}/LICENSE ${INSTALL}/usr/share/licenses/${PKG_NAME}/LICENSE
      if [ "${ENABLE_32BIT}" = true ]; then
        arm="${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/${PKG_NAME}-${PKG_VERSION}"
        [ -f "${arm}/usr/lib-rknnrt32/librknnrt.so" ] || die "${PKG_NAME}: build it for ARCH=arm first"
        mkdir -p ${INSTALL}/usr/lib32
        install -m 0644 ${arm}/usr/lib-rknnrt32/librknnrt.so ${INSTALL}/usr/lib32/librknnrt.so
      fi
      ;;
  esac
}
