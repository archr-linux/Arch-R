# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rk915"
PKG_REV="2"
PKG_VERSION="e2fd61651c272aab7bd7e76ba05e5682d7c1d211"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/AveyondFly/rk915"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="RK915 WiFi/BT SDIO driver"
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  kernel_make -C $(kernel_path) M=${PKG_BUILD} \
    BUSIF=SDIO \
    ROM=true \
    CHIP=RK915
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
  cp ${PKG_BUILD}/*.ko ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}

  # Install firmware to kernel overlay
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)
  cp ${PKG_BUILD}/firmware/*.bin ${INSTALL}/$(get_full_firmware_dir)/
}
