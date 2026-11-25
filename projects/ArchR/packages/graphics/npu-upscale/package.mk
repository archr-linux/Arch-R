# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="npu-upscale"
PKG_REV="1"
PKG_ARCH="aarch64 arm"
# NPU UPSCALE from dArkOS for the RG52 Mini by mamaich
# (https://github.com/mamaich/dArkOS_rg52mini, npusr/ and npusr-gles/):
# an emulator's native frame, shown enlarged by an integer, nearest, is
# enlarged instead by a small super-resolution network on the RK3562's NPU.
# Taken here: libnpusr_gles.so (an LD_PRELOAD for EGL/GLES programs, no change
# to the emulator), its models and its notice. dArkOS's Vulkan layer is not
# taken: the RK3562's libmali (g24p0) has no Vulkan. Needs the rknpu driver
# and Rockchip's librknnrt.
PKG_VERSION="902ce716ef49c8f18a5adc4ead4c51db40a8c96f"
PKG_LICENSE="MIT"
PKG_SITE="https://github.com/mamaich/dArkOS_rg52mini"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain ${OPENGLES} librknnrt"
PKG_LONGDESC="NPU UPSCALE: emulator frames enlarged by a neural network on the RK3562 NPU (from dArkOS)"
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD}/npusr-gles
  cp ${PKG_BUILD}/vk-rotate-layer/rknn_api.h .
  ${CC} ${CFLAGS} -O2 -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers \
    -fPIC -shared -fvisibility=hidden -DEGL_NO_X11 -I. \
    -o libnpusr_gles.so npusr_gles.c ${LDFLAGS} -ldl -lpthread -lm
}

# arm: only the 32-bit library, kept out of the arm image's /usr/lib (lib32
# copies that whole tree). aarch64: everything, the arm library in /usr/lib32
# for the 32-bit RetroArch (pcsx_rearmed32, PS1's default core).
makeinstall_target() {
  if [ "${TARGET_ARCH}" = arm ]; then
    mkdir -p ${INSTALL}/usr/lib-npusr32
    install -m 0755 ${PKG_BUILD}/npusr-gles/libnpusr_gles.so ${INSTALL}/usr/lib-npusr32/libnpusr_gles.so
    return 0
  fi
  mkdir -p ${INSTALL}/usr/lib ${INSTALL}/usr/bin ${INSTALL}/usr/share/npu-upscale \
    ${INSTALL}/usr/share/licenses/${PKG_NAME}
  install -m 0755 ${PKG_BUILD}/npusr-gles/libnpusr_gles.so ${INSTALL}/usr/lib/libnpusr_gles.so
  if [ "${ENABLE_32BIT}" = true ]; then
    arm="${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/${PKG_NAME}-${PKG_VERSION}"
    [ -f "${arm}/usr/lib-npusr32/libnpusr_gles.so" ] || die "${PKG_NAME}: build it for ARCH=arm first"
    mkdir -p ${INSTALL}/usr/lib32
    install -m 0755 ${arm}/usr/lib-npusr32/libnpusr_gles.so ${INSTALL}/usr/lib32/libnpusr_gles.so
  fi
  # x2 for the PSP (960x544 on the RG43V's 1024x768), x3 for the PSP and the
  # 3DS on 816-line screens, x3 for PS1 and the 16-bit consoles
  for m in espcn_x2_480x272 espcn_x3_480x272 espcn_x3_400x240 x3_256x224 x3_256x240 \
           x3_304x224 x3_320x224 x3_320x240 x3_368x224 x3_368x240; do
    install -m 0644 ${PKG_BUILD}/npusr/models/${m}.rknn ${INSTALL}/usr/share/npu-upscale/
  done
  install -m 0755 ${PKG_DIR}/sources/npu-upscale ${INSTALL}/usr/bin/npu-upscale
  install -m 0644 ${PKG_BUILD}/npusr/NOTICE ${INSTALL}/usr/share/licenses/${PKG_NAME}/NOTICE.dArkOS
  install -m 0644 ${PKG_BUILD}/npusr/models/LICENSE-TF-ESPCN ${INSTALL}/usr/share/licenses/${PKG_NAME}/
  install -m 0644 ${PKG_BUILD}/LICENSES.md ${INSTALL}/usr/share/licenses/${PKG_NAME}/LICENSES.dArkOS.md
  install -m 0644 ${PKG_BUILD}/npusr-gles/README.md ${INSTALL}/usr/share/licenses/${PKG_NAME}/README-gles.dArkOS.md
}
