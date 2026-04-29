# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021-present 351ELEC (https://github.com/351ELEC)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="retroarch"
PKG_VERSION="fae7468de15b32a0e105e45325e5ca85e62ea7d4" # v1.22.2 + fixes
PKG_SITE="https://github.com/libretro/RetroArch"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LICENSE="GPLv3"
PKG_DEPENDS_TARGET="toolchain SDL2 alsa-lib libass openssl freetype zlib retroarch-assets core-info ffmpeg libass joyutils nss-mdns openal-soft libogg libvorbisidec libvorbis libvpx libpng libdrm pulseaudio miniupnpc flac xz"
PKG_LONGDESC="Reference frontend for the libretro API."
PKG_BUILD_FLAGS="+speed +lto"

if [ "${PIPEWIRE_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" pipewire"
fi

case ${ARCH} in
  arm)
    true
    ;;
  *)
    PKG_DEPENDS_TARGET+=" empty"
    ;;
esac

PKG_PATCH_DIRS+=" ${DEVICE}"

PKG_CONFIGURE_OPTS_TARGET="   --disable-qt \
                              --enable-alsa \
                              --enable-udev \
                              --disable-opengl1 \
                              --disable-x11 \
                              --enable-zlib \
                              --enable-freetype \
                              --disable-discord \
                              --disable-vg \
                              --disable-sdl \
                              --enable-sdl2 \
                              --enable-kms \
                              --enable-ffmpeg"

case ${ARCH} in
  arm)
    PKG_CONFIGURE_OPTS_TARGET+=" --enable-neon"
  ;;
    aarch64)
    PKG_CONFIGURE_OPTS_TARGET+=" --disable-neon"
  ;;
esac

case ${DEVICE} in
  RK*)
    PKG_DEPENDS_TARGET+=" librga"
  ;;
esac

if [ "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" wayland wayland-protocols wayland:host"
  PKG_CONFIGURE_OPTS_TARGET+=" --enable-wayland"
  case ${ARCH} in
    arm)
      true
      ;;
    *)
      PKG_DEPENDS_TARGET+=" ${WINDOWMANAGER}"
      ;;
  esac
else
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-wayland"
fi

if [ "${OPENGLES_SUPPORT}" = "yes" ] && \
	[ "${PREFER_GLES}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGLES}"
    # --enable-opengles3 required for glcore, --enable-opengles3_1 doesn't auto-select it
    PKG_CONFIGURE_OPTS_TARGET+=" --enable-opengles --enable-opengles3 --enable-opengles3_1"
    PKG_CONFIGURE_OPTS_TARGET+=" --disable-opengl"
else
	# Full OpenGL
    PKG_DEPENDS_TARGET+=" ${OPENGL} glu libglvnd"
    PKG_CONFIGURE_OPTS_TARGET+=" --enable-opengl"
    PKG_CONFIGURE_OPTS_TARGET+=" --disable-opengles --disable-opengles3 --disable-opengles3_1 --disable-opengles3_2"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]
then
    PKG_DEPENDS_TARGET+=" ${VULKAN}"
    PKG_CONFIGURE_OPTS_TARGET+=" --enable-vulkan --enable-vulkan_display"
else
  PKG_CONFIGURE_OPTS_TARGET+=" --disable-vulkan"
fi

pre_configure_target() {
  CFLAGS+=" -DUDEV_TOUCH_SUPPORT -I${SYSROOT_PREFIX}/usr/include/spa-0.2 -I${SYSROOT_PREFIX}/usr/include/pipewire-0.3"
  CXXFLAGS+=" -DUDEV_TOUCH_SUPPORT -I${SYSROOT_PREFIX}/usr/include/spa-0.2 -I${SYSROOT_PREFIX}/usr/include/pipewire-0.3"
  TARGET_CONFIGURE_OPTS=""

  # Tell retroarch configure this is a cross-compilation
  # Without this, qb/config.libs.sh adds -L/usr/lib64 from the host
  export CROSS_COMPILE="${TARGET_PREFIX}"

  # Fix retroarch qb cross-compilation: patch config.libs.sh to use sysroot paths
  if [ -n "${SYSROOT_PREFIX}" ]; then
    sed -i "s|INCLUDES='usr/include usr/local/include'|INCLUDES='${SYSROOT_PREFIX}/usr/include ${SYSROOT_PREFIX}/usr/local/include'|" ${PKG_BUILD}/qb/config.libs.sh
  fi

  # Ensure retroarch configure finds pkg-config (it looks for ${CROSS_COMPILE}pkg-config which doesn't exist)
  export PKG_CONF_PATH="${TOOLCHAIN}/bin/pkg-config"
  # Ensure pkg-config finds wayland-protocols in share/pkgconfig and wayland-scanner in toolchain
  export PKG_CONFIG_PATH="${SYSROOT_PREFIX}/usr/lib/pkgconfig:${SYSROOT_PREFIX}/usr/share/pkgconfig:${TOOLCHAIN}/lib/pkgconfig:${TOOLCHAIN}/share/pkgconfig"

  # Disable pipewire for arm 32-bit compat (headers not in arm sysroot)
  if [ "${TARGET_ARCH}" = "arm" ]; then
    PKG_CONFIGURE_OPTS_TARGET+=" --disable-pipewire"
  fi

  cd ${PKG_BUILD}
}

make_target() {
  make HAVE_UPDATE_ASSETS=0 HAVE_LIBRETRODB=1 HAVE_BLUETOOTH=0 HAVE_NETWORKING=1 HAVE_ZARCH=1 HAVE_QT=0 HAVE_LANGEXTRA=1
  [ $? -eq 0 ] && echo "(retroarch ok)" || { echo "(retroarch failed)" ; exit 1 ; }
  make -C gfx/video_filters compiler=$CC extra_flags="$CFLAGS"
  [ $? -eq 0 ] && echo "(video filters ok)" || { echo "(video filters failed)" ; exit 1 ; }
  make -C libretro-common/audio/dsp_filters compiler=$CC extra_flags="$CFLAGS"
  [ $? -eq 0 ] && echo "(audio filters ok)" || { echo "(audio filters failed)" ; exit 1 ; }
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/retroarch ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/share/retroarch/filters

  case ${ARCH} in
    aarch64)
      if [ -f ${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/retroarch-*/usr/bin/retroarch ]; then
        cp -vP ${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/retroarch-*/usr/bin/retroarch ${INSTALL}/usr/bin/retroarch32
        mkdir -p ${INSTALL}/usr/share/retroarch/filters/32bit/
        cp -rvP ${ROOT}/build.${DISTRO}-${DEVICE}.arm/install_pkg/retroarch-*/usr/share/retroarch/filters/64bit/* ${INSTALL}/usr/share/retroarch/filters/32bit/
      fi
    ;;
  esac

  mkdir -p ${INSTALL}/etc
  cp ${PKG_BUILD}/retroarch.cfg ${INSTALL}/etc

  mkdir -p ${INSTALL}/usr/share/retroarch/filters/64bit/video
  cp ${PKG_BUILD}/gfx/video_filters/*.so ${INSTALL}/usr/share/retroarch/filters/64bit/video
  cp ${PKG_BUILD}/gfx/video_filters/*.filt ${INSTALL}/usr/share/retroarch/filters/64bit/video

  mkdir -p ${INSTALL}/usr/share/retroarch/filters/64bit/audio
  cp ${PKG_BUILD}/libretro-common/audio/dsp_filters/*.so ${INSTALL}/usr/share/retroarch/filters/64bit/audio
  cp ${PKG_BUILD}/libretro-common/audio/dsp_filters/*.dsp ${INSTALL}/usr/share/retroarch/filters/64bit/audio

  # General configuration
  mkdir -p ${INSTALL}/usr/config/retroarch/
  if [ -d "${PKG_DIR}/sources/${DEVICE}" ]; then
    cp -rf ${PKG_DIR}/sources/${DEVICE}/* ${INSTALL}/usr/config/retroarch/
  else
    echo "Configure retroarch for ${DEVICE}"
    exit 1
  fi

  # Make sure the shader directories exist for overlayfs.
  for dir in common-shaders glsl-shaders slang-shaders
  do
    mkdir -p ${INSTALL}/usr/share/${dir}
    touch ${INSTALL}/usr/share/${dir}/.overlay
  done

  # Copy achievment sounds
  mkdir -p ${INSTALL}/usr/share/libretro
    cp -R ${PKG_DIR}/sounds ${INSTALL}/usr/share/libretro

    # Copy achievements hooks script
    cp ${PKG_DIR}/scripts/call_achievements_hooks.sh ${INSTALL}/usr/share/libretro
}

post_install() {
  enable_service tmp-cores.mount
  enable_service tmp-database.mount
  enable_service tmp-assets.mount
  enable_service tmp-shaders.mount
  enable_service tmp-overlays.mount
}
