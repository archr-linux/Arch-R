# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="ppsspp-2021-arch"
PKG_VERSION="ce0a45cf0fcdd5bebf32208b9998f68dfc1107b7" # v1.12.3
PKG_SITE="https://github.com/hrydgard/ppsspp"
PKG_URL="${PKG_SITE}.git"
PKG_LICENSE="GPLv2"
PKG_DEPENDS_TARGET="toolchain libzip SDL2 zlib ${OPENGLES}"
PKG_LONGDESC="PPSSPP v1.12.3, the release dArkOS keeps beside the current one for the RK3326: heavy games (God of War) run faster on the Mali-G31. Patches from christianhaitian/rk3326_core_builds (-Ofast, FMV stutter)."
GET_HANDLER_SUPPORT="git"
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET=" -DUSE_SYSTEM_FFMPEG=OFF \
                        -DCMAKE_BUILD_TYPE=Release \
                        -DCMAKE_SYSTEM_NAME=Linux \
                        -DBUILD_SHARED_LIBS=OFF \
                        -DUSE_SYSTEM_LIBPNG=OFF \
                        -DUSE_FFMPEG=ON \
                        -DUSING_QT_UI=OFF \
                        -DUNITTEST=OFF \
                        -DSIMULATOR=OFF \
                        -DHEADLESS=OFF \
                        -DUSE_DISCORD=OFF \
                        -DUSING_FBDEV=ON \
                        -DUSING_EGL=OFF \
                        -DUSING_GLES2=ON \
                        -DVULKAN=OFF \
                        -DUSING_X11_VULKAN=OFF \
                        -DUSE_WAYLAND_WSI=OFF"

pre_configure_target() {
  # 2021 code: GCC 14 no longer pulls <cstdint> in through other headers.
  export CXXFLAGS="${CXXFLAGS} -Wno-error -fpermissive -include cstdint"
  sed -i "s|include_directories(/usr/include/drm)|include_directories(${SYSROOT_PREFIX}/usr/include/drm)|" ${PKG_BUILD}/CMakeLists.txt
}

pre_make_target() {
  export CPPFLAGS="${CPPFLAGS} -Wno-error"
  export CFLAGS="${CFLAGS} -Wno-error"
  find ${PKG_BUILD} -name flags.make -exec sed -i "s:isystem :I:g" \{} \;
  find ${PKG_BUILD} -name build.ninja -exec sed -i "s:isystem :I:g" \{} \;
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin ${INSTALL}/usr/share/ppsspp-2021
  cp PPSSPPSDL ${INSTALL}/usr/bin/ppsspp-2021
  chmod 0755 ${INSTALL}/usr/bin/ppsspp-2021
  cp -r assets ${INSTALL}/usr/share/ppsspp-2021/
}
