# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="gpudriver"
PKG_VERSION=""
PKG_LICENSE="GPLv2"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET=""
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="GPU driver util for switching between panfrost / panthor and libmali / libmali-vulkan"

post_makeinstall_target() {
  # Installed as /usr/bin/gpudriver. EmulationStation surfaces the GPU
  # DRIVER selector only when that exact path exists (see es-app
  # GuiMenu.cpp), so the location IS the feature flag. It lived under
  # /usr/lib/archr/ for a while to hide the picker while the panfrost
  # probe could still hang the kernel on RK3326 clones; the guards that
  # made hiding unnecessary are all in the script now: the
  # /storage/.config/gpudriver.attempting sentinel written with
  # oflag=sync forces libmali on the boot after a crash, the async
  # modprobe with a bind poll survives a blocked probe, and gpu_is_bound
  # falls back to the other driver when the requested one does not
  # attach. libmali stays the default. Anything else that shells out to
  # the tool (the 075-mangohud-supported quirk) also expects /usr/bin.
  mkdir -p "${INSTALL}/usr/bin/"
  cp -v "${PKG_BUILD}/bin/gpudriver" "${INSTALL}/usr/bin/"
  GPUDRIVER_BIN="${INSTALL}/usr/bin/gpudriver"

  # set the correct mesa pan kernel driver module based on device
  case ${DEVICE} in
    RK3588)
      PAN="panthor"
      DTB_OVERLAY_GPU="driver-gpu-panthor.dtbo"
    ;;
    S922X)
      PAN="panfrost"
      DTB_OVERLAY_GPU="driver-gpu-panfrost.dtbo"
    ;;
    *)
      # No DTB overlay needed: kernel base DTS already has the GPU node
      # with 'arm,mali-bifrost' compatible, so panfrost binds directly
      # via modprobe. Switching between libmali and panfrost just
      # requires loading/unloading the kernel module and swapping the
      # userspace GL library binds.
      PAN="panfrost"
      DTB_OVERLAY_GPU=""
    ;;
  esac

  sed -e "s/@PAN@/${PAN}/g" \
      -i  "${GPUDRIVER_BIN}"

  sed -e "s/@DTB_OVERLAY_GPU@/${DTB_OVERLAY_GPU}/g" \
      -i  "${GPUDRIVER_BIN}"
}