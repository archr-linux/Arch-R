# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2022-present 351ELEC
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="yabasanshiro-arch"
PKG_REPLACES="yabasanshiro-sa"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/pirrypirrypirry/yabasanshiro-pirry"
PKG_URL="${PKG_SITE}.git"
# v1.6.2
PKG_VERSION="ba771f1791bf59b858b2ffdbc25b3cf04a4d8996"
PKG_REV="3"
PKG_ARCH="aarch64"
# curl is dlopen()ed at run time (libcurl.so.4) for RetroAchievements
PKG_DEPENDS_TARGET="toolchain SDL2 openal-soft zlib libpng curl"
PKG_LONGDESC="Yaba Sanshiro Sega Saturn emulator, optimized for RK3326 handhelds (yabasanshiro-pirry)"
PKG_TOOLCHAIN="cmake-make"
GET_HANDLER_SUPPORT="git"
PKG_BUILD_FLAGS="+speed"

if [ "${OPENGLES_SUPPORT}" = yes ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
fi

post_unpack() {
  # use host versions
  sed -i "s|COMMAND m68kmake|COMMAND ${PKG_BUILD}/m68kmake_host|" ${PKG_BUILD}/yabause/src/musashi/CMakeLists.txt
  sed -i "s|COMMAND ./bin2c|COMMAND ${PKG_BUILD}/bin2c_host|" ${PKG_BUILD}/yabause/src/retro_arena/nanogui-sdl/CMakeLists.txt
  find ${PKG_BUILD} -type f -name "CMakeLists.txt" -exec sed -i 's/^\s*cmake_minimum_required.*$/cmake_minimum_required(VERSION 3.5)/' {} +
}

pre_make_target() {
  # runs on host so make them manually if package is not crosscompile friendly
  ${HOST_CC} ${PKG_BUILD}/yabause/src/retro_arena/nanogui-sdl/resources/bin2c.c -o ${PKG_BUILD}/bin2c_host
  ${HOST_CC} ${PKG_BUILD}/yabause/src/musashi/m68kmake.c -o ${PKG_BUILD}/m68kmake_host
}

pre_configure_target() {
  # Upstream's documented RK3326 build (README "Building"); -mcpu=cortex-a35
  # already comes from TARGET_CPU. The fork's own __N2__/ARM7 switches are
  # not used: its release build does not set them either.
  CFLAGS+=" -fno-strict-aliasing -D_GNU_SOURCE -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-int-conversion"
  CXXFLAGS+=" -fno-strict-aliasing -D_GNU_SOURCE"
  # nvgCreateGLES3 is defined twice in the bundled nanovg/nanogui code
  LDFLAGS+=" -Wl,--allow-multiple-definition"

  PKG_CMAKE_OPTS_TARGET="${PKG_BUILD}/yabause \
                         -DCMAKE_BUILD_TYPE=Release \
                         -DYAB_PORTS=retro_arena \
                         -DYAB_WANT_DYNAREC_DEVMIYAX=ON \
                         -DYAB_WANT_VULKAN=OFF \
                         -DUSE_EGL=ON \
                         -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
                         -Dpng_STATIC_LIBRARIES=${SYSROOT_PREFIX}/usr/lib/libpng16.so \
                         -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a ${PKG_BUILD}/src/retro_arena/yabasanshiro ${INSTALL}/usr/bin/yabasanshiro
  cp -a ${PKG_DIR}/scripts/start_yabasanshiro.sh ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/start_yabasanshiro.sh
  mkdir -p ${INSTALL}/usr/config/yabasanshiro
  cp ${PKG_DIR}/config/config ${INSTALL}/usr/config/yabasanshiro/.config
  cp -r ${PKG_DIR}/config/devices ${INSTALL}/usr/config/yabasanshiro/
}
