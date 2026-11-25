# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-2024 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2024-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="rkbin"
PKG_LICENSE="nonfree"
PKG_SITE="https://github.com/rockchip-linux/rkbin"
PKG_LONGDESC="rkbin: Rockchip Firmware and Tool Binaries"
PKG_TOOLCHAIN="manual"

case "${DEVICE}" in
  RK3588)
    # Pin rk3588 here until it hits mainline
    PKG_VERSION="7c35e21a8529b3758d1f051d1a5dc62aae934b2b"
    ;;
  RK3326)
    # 2026-06-24: rk3326_bl31_v1.37 ("DDR frequency scaling occasionally
    # causes kernel panic"). This tree ships the DDR init as v2.12 (v2.11
    # is gone; v2.12 only adds DDR security fixes, same parameters).
    PKG_VERSION="2eca6e24fc6f8cf879b4f2f204b9c8acdfe37518"
    ;;
  *)
    PKG_VERSION="74213af1e952c4683d2e35952507133b61394862"
    ;;
esac

PKG_URL="https://github.com/rockchip-linux/rkbin/archive/${PKG_VERSION}.tar.gz"

post_unpack() {
 if [ "${DEVICE}" == "RK3326" ]; then
  # RK3326: the stock TPL blob initialises every DDR type at 333MHz and
  # mainline has no px30 dmc driver, so the memory stays at 333MHz for
  # the life of the system. That is far below what the BSP-based OSes on
  # the same boards run: dArkOS scales the DDR with dmc_ondemand up to
  # the 786MHz BSP ceiling and pins 528MHz even in its powersave mode.
  # Rewrite the frequency fields inside the TPL with Rockchip's own
  # ddrbin_tool (the long-standing ArkOS "DDR fix") so the memory comes
  # up at speed from boot.
  #
  # 786MHz failed the hardware boot test (2026-07-02, R36S): the screen
  # lights and the SoC resets in a loop before U-Boot, i.e. the TPL DDR
  # training does not converge at that speed on a fixed cold init (dArkOS
  # only reaches 786 through the BSP dmc driver's runtime retraining).
  # The subsequent "666 and even 333 also fail" scare turned out to be
  # stale flash copies of the 786 image: a full hardware bisect booted
  # every combination at 333, and the TPL frequency bytes were verified
  # inside each disk image (signature at idbloader+0x27bc). 666MHz is the
  # conservative step (still 2x the old 333); drop to 528 (dArkOS's own
  # powersave floor) if a board genuinely fails at 666.
  RK3326_DDR_FREQ="${RK3326_DDR_FREQ:-666}"
  DDR_BIN="$(ls ${PKG_BUILD}/bin/rk33/rk3326_ddr_333MHz_*.bin)"

  # Keep an untouched copy of the stock 333MHz TPL before retuning. Some
  # boards fail DDR training at 666 (clone rev 2547, issue #31) and the
  # hardware bisect showed stock 333 boots everything — this copy becomes
  # the "DDR failsafe" loader assembled by the u-boot package.
  cp ${DDR_BIN} ${PKG_BUILD}/rk3326_ddr_fallback333.bin
  ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 -g ${PKG_BUILD}/rk3326_ddr_freq.txt ${DDR_BIN}
  sed -i -E "s#^(lp2_freq|ddr3_freq|lp3_freq|ddr4_freq|lp4_freq)=.*#\1=${RK3326_DDR_FREQ}#" ${PKG_BUILD}/rk3326_ddr_freq.txt
  ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 ${PKG_BUILD}/rk3326_ddr_freq.txt ${DDR_BIN} >/dev/null
  echo "rkbin: RK3326 TPL DDR frequency set to ${RK3326_DDR_FREQ}MHz"

  # tune a second TPL copy for UART5 used on K36 clones (inherits the
  # DDR frequency edit above)
  cp -v ${DDR_BIN} ${PKG_BUILD}/rk3326_ddr_uart5.bin
  ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 -g ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin
  sed -i 's|uart id=.*$|uart id=5|' ${PKG_BUILD}/rk3326_ddr_uart5.txt
  ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin >/dev/null
 fi
}
