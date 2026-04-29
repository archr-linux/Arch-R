# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="u-boot-legacy"
PKG_VERSION="2492a3e467e332e2350d987234ce6123700b3392"
PKG_LICENSE="GPL"
PKG_SITE="https://www.denx.de/wiki/U-Boot"
PKG_URL="https://github.com/archr-linux/hardkernel-uboot/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain Python3:host swig:host pyelftools:host"
PKG_LONGDESC="Das U-Boot is a cross-platform bootloader for embedded systems."
PKG_BUILD_FLAGS="-parallel"
PKG_TOOLCHAIN="manual"

PKG_NEED_UNPACK="${PROJECT_DIR}/${PROJECT}/bootloader ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/bootloader"
PKG_NEED_UNPACK+=" ${PROJECT_DIR}/${PROJECT}/options ${PROJECT_DIR}/${PROJECT}/devices/${DEVICE}/options"

if [ -n "${UBOOT_FIRMWARE}" ]; then
  PKG_DEPENDS_TARGET+=" ${UBOOT_FIRMWARE}"
  PKG_DEPENDS_UNPACK+=" ${UBOOT_FIRMWARE}"
fi

post_unpack() {
  # Fix BSP U-Boot to load DTBs from dtbs/ subfolder and use correct DTB names
  # board.c: fatload from dtbs/ instead of root
  sed -i 's|fatload mmc 1:1 ${fdt_addr_r} ${dtb_name}|fatload mmc 1:1 ${fdt_addr_r} dtbs/${dtb_name}|' \
    ${PKG_BUILD}/arch/arm/mach-rockchip/board.c

  # hwrev.c: use correct DTB names matching kernel device trees
  sed -i \
    -e 's|rk3326-odroidgo2-linux-v11.dtb|rk3326-odroid-go2-v11.dtb|' \
    -e 's|rk3326-odroidgo2-linux.dtb|rk3326-odroid-go2.dtb|' \
    -e 's|rk3326-odroidgo3-linux.dtb|rk3326-odroid-go3.dtb|' \
    ${PKG_BUILD}/cmd/hwrev.c
}

pre_make_target() {
  PKG_UBOOT_CONFIG="archr_rk3326_defconfig"
  PKG_RKBIN="$(get_build_dir rkbin)"
  PKG_MINILOADER="${PKG_RKBIN}/bin/rk33/rk3326_miniloader_v1.40.bin"
  PKG_BL31="${PKG_RKBIN}/bin/rk33/rk3326_bl31_v1.34.elf"
  PKG_DDR_BIN="${PKG_RKBIN}/bin/rk33/rk3326_ddr_333MHz_v2.11.bin"
}

make_target() {
  [ "${BUILD_WITH_DEBUG}" = "yes" ] && PKG_DEBUG=1 || PKG_DEBUG=0
  setup_pkg_config_host

  DEBUG=${PKG_DEBUG} CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" LDFLAGS="" ARCH=arm make mrproper
  DEBUG=${PKG_DEBUG} CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" LDFLAGS="" ARCH=arm make ${PKG_UBOOT_CONFIG}
  DEBUG=${PKG_DEBUG} CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" LDFLAGS="" ARCH=arm _python_sysroot="${TOOLCHAIN}" _python_prefix=/ _python_exec_prefix=/ make HOSTCC="$HOST_CC" HOSTLDFLAGS="-L${TOOLCHAIN}/lib" HOSTSTRIP="true" CONFIG_MKIMAGE_DTC_PATH="scripts/dtc/dtc"

  find_file_path bootloader/rkhelper && . ${FOUND_PATH}
}

makeinstall_target() {
  mkdir -p $INSTALL/usr/share/bootloader

  cp -av uboot.bin $INSTALL/usr/share/bootloader/original_uboot.bin
}
