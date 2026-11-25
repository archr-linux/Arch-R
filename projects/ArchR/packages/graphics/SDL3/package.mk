# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="SDL3"
PKG_VERSION="3.4.20"
PKG_SHA256="f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f"
PKG_ARCH="aarch64"
PKG_LICENSE="Zlib"
PKG_SITE="https://www.libsdl.org/"
PKG_URL="https://github.com/libsdl-org/SDL/releases/download/release-${PKG_VERSION}/SDL3-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain alsa-lib systemd dbus pulseaudio pipewire libdrm"
PKG_LONGDESC="SDL3 runtime (libSDL3.so.0) for ports built against SDL3, such as Dusklight. Lives next to SDL2 and does not replace it; same backends as the system SDL2."
PKG_TOOLCHAIN="cmake"
PKG_BUILD_FLAGS="+speed"

# Backends follow the SDL2 package (graphics/SDL2): Wayland, KMSDRM,
# GLES/EGL, desktop GL, Vulkan, ALSA, PipeWire and PulseAudio; no X11.
PKG_CMAKE_OPTS_TARGET="-DSDL_SHARED=ON \
                       -DSDL_STATIC=OFF \
                       -DSDL_TEST_LIBRARY=OFF \
                       -DSDL_TESTS=OFF \
                       -DSDL_EXAMPLES=OFF \
                       -DSDL_INSTALL_DOCS=OFF \
                       -DSDL_RPATH=OFF \
                       -DSDL_LIBC=ON \
                       -DSDL_GCC_ATOMICS=ON \
                       -DSDL_PTHREADS=ON \
                       -DSDL_PTHREADS_SEM=ON \
                       -DSDL_ALSA=ON \
                       -DSDL_ALSA_SHARED=ON \
                       -DSDL_PIPEWIRE=ON \
                       -DSDL_PIPEWIRE_SHARED=ON \
                       -DSDL_PULSEAUDIO=ON \
                       -DSDL_PULSEAUDIO_SHARED=ON \
                       -DSDL_JACK=OFF \
                       -DSDL_SNDIO=OFF \
                       -DSDL_OSS=OFF \
                       -DSDL_DISKAUDIO=OFF \
                       -DSDL_DUMMYAUDIO=OFF \
                       -DSDL_DUMMYVIDEO=OFF \
                       -DSDL_X11=OFF \
                       -DSDL_VIVANTE=OFF \
                       -DSDL_RPI=OFF \
                       -DSDL_ROCKCHIP=OFF \
                       -DSDL_OPENVR=OFF \
                       -DSDL_LIBURING=OFF \
                       -DSDL_IBUS=OFF \
                       -DSDL_HIDAPI=ON \
                       -DSDL_HIDAPI_JOYSTICK=ON \
                       -DSDL_LIBUDEV=ON \
                       -DSDL_DBUS=ON"

if [ ! "${OPENGL_SUPPORT}" = "no" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL}"
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_OPENGL=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_OPENGL=OFF"
fi

if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_OPENGLES=ON \
                           -DSDL_KMSDRM=ON \
                           -DSDL_KMSDRM_SHARED=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_OPENGLES=OFF \
                           -DSDL_KMSDRM=OFF"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_VULKAN=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_VULKAN=OFF \
                           -DSDL_RENDER_VULKAN=OFF"
fi

if [ "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" wayland wayland-protocols libxkbcommon"
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_WAYLAND=ON \
                           -DSDL_WAYLAND_SHARED=ON \
                           -DSDL_WAYLAND_LIBDECOR=OFF"
else
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_WAYLAND=OFF"
fi

# The image gets the runtime only: headers, CMake and pkg-config files stay
# in the sysroot for packages that build against SDL3.
post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/bin ${INSTALL}/usr/include ${INSTALL}/usr/share
  rm -rf ${INSTALL}/usr/lib/cmake ${INSTALL}/usr/lib/pkgconfig
  rm -f ${INSTALL}/usr/lib/libSDL3.so
}
