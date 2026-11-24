# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

# AICSemi AIC8800 over SDIO (aic8800_bsp + aic8800_fdrv + aic8800_btlpm), the
# Wi-Fi of the RK3562 AISLPC boards rev. v14 (RG43V PRO, RG52 MINI). The stock
# firmware ships the same fdrv 6.4.3.0 with AIC8800D80 firmware only.
#
# Source: radxa-pkg/aic8800, the AICSemi SDK V5.0 (2026-01-23) plus Radxa's
# Debian patch series, which tracks new kernels (6.13 to 7.4). Its src/SDIO
# part is folded into patches/0001. Not to be confused with the USB driver
# in ../AIC8800 (different modules, firmware dir /lib/firmware/aic8800DC).
#
# The chip is picked by its SDIO ID: aic8800_fdrv carries the aliases of the
# whole family (c8a1:0082 D80, 9081-9086 D80N/D40N, 2082 D80X2, c8a1:c08d DC,
# 5449:0145 8801), so udev loads it on a v14 board and never on a v10 (rk915,
# 0296:5347/5348). aic8800_bsp comes in as its symbol dependency.
PKG_NAME="AIC8800-SDIO"
PKG_REV="1"
PKG_VERSION="5562c254b0231be34588dc608ec28c4f1d613285"
PKG_SHA256="a5d1dc573c07b23fa50fba653ae51da11e2d74e2ecfdd6d0a1cf6afa9a06be74"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/radxa-pkg/aic8800"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="AIC8800 SDIO WiFi out-of-tree driver (aic8800_bsp + aic8800_fdrv)"
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

AIC8800_SDIO_SRC="src/SDIO/driver_fw/driver/aic8800"

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  kernel_make -C $(kernel_path) M=${PKG_BUILD}/${AIC8800_SDIO_SRC} modules
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
  cp ${PKG_BUILD}/${AIC8800_SDIO_SRC}/aic8800_bsp/aic8800_bsp.ko \
     ${PKG_BUILD}/${AIC8800_SDIO_SRC}/aic8800_fdrv/aic8800_fdrv.ko \
     ${PKG_BUILD}/${AIC8800_SDIO_SRC}/aic8800_btlpm/aic8800_btlpm.ko \
     ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}

  # The bsp opens /lib/firmware/aic8800_fw/SDIO/<family>/ itself (filp_open,
  # no request_firmware). Only the D80 family: the stock v14 firmware has
  # D80 files only; D80N and D80X2 cover a later board respin at ~1 MB.
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/aic8800_fw/SDIO
  for fw in aic8800D80 aic8800D80N aic8800D80X2; do
    cp -a ${PKG_BUILD}/src/SDIO/driver_fw/fw/${fw} \
       ${INSTALL}/$(get_full_firmware_dir)/aic8800_fw/SDIO/
  done
}
