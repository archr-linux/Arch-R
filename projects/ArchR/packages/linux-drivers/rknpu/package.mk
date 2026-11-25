# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="rknpu"
PKG_REV="1"
# Rockchip's RKNPU driver (BSP 0.9.x) ported to the mainline kernel out of
# tree by simonswine/rknpu-mainline: the DRM render node and ioctls that
# Rockchip's librknnrt speaks. Mainline's accel/rocket covers only the
# RK3588 and speaks Mesa Teflon, not librknnrt. Only the RK3562 builds it
# (its NPU node is in the RK3562 device tree, IOMMU mode).
PKG_VERSION="a9ee21fa41d447c3f3f49b47184ca6ae8523b801"
PKG_LICENSE="GPL-2.0-only"
PKG_SITE="https://github.com/simonswine/rknpu-mainline"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="rknpu: Rockchip RKNPU driver for the mainline kernel"
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

make_target() {
  kernel_make -C $(kernel_path) M=${PKG_BUILD} modules
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
  cp ${PKG_BUILD}/rknpu.ko ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
}
