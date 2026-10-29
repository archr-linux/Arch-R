# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="system-utils"
PKG_VERSION="2.1"
PKG_REV="5"
PKG_LICENSE="mix"
PKG_DEPENDS_TARGET="toolchain sleep"
PKG_SITE=""
PKG_URL=""
PKG_LONGDESC="Hardware button support scripts."
PKG_TOOLCHAIN="manual"

makeinstall_target() {

  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/sources/autostart/common/* ${INSTALL}/usr/lib/autostart/common

  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/fancontrol ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/headphone_sense ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/hdmi_sense ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/input_sense ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/ledcontrol ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/battery_led_status ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/turbomode ${INSTALL}/usr/bin
  if [ -d "${PKG_DIR}/sources/devices/${DEVICE}" ]
  then
    cp ${PKG_DIR}/sources/devices/${DEVICE}/* ${INSTALL}/usr/bin
    if [ -d "${PKG_DIR}/sources/autostart/${DEVICE}" ]
    then
      mkdir -p ${INSTALL}/usr/lib/autostart/${DEVICE}
      cp ${PKG_DIR}/sources/autostart/${DEVICE}/* ${INSTALL}/usr/lib/autostart/${DEVICE}
      chmod 0755 ${INSTALL}/usr/lib/autostart/${DEVICE}/*
    fi
  fi
  chmod 0755 ${INSTALL}/usr/bin/*

  # video.service runs /usr/bin/video_sense which only ships for a few
  # devices (RK3399 / RK3566 / S922X). When the binary isn't installed
  # the unit becomes orphan (ExecStart pointing at nowhere). Drop the
  # unit on devices without the helper so systemd-analyze stays clean.
  if [ ! -f ${INSTALL}/usr/bin/video_sense ]; then
    rm -f ${INSTALL}/usr/lib/systemd/system/video.service
  fi

  mkdir -p ${INSTALL}/usr/config
  cp ${PKG_DIR}/sources/config/fancontrol.conf ${INSTALL}/usr/config/fancontrol.conf.sample
}


post_install() {
  # input_sense owns the power-button path on RK3326 (KEY_POWER from the
  # rk817 pwrkey drives archr-fake-suspend) and the R33S/RG351 quirks
  # already assume the unit is running, yet nothing ever enabled it, so
  # the power button only reached logind's (broken) kernel suspend.
  # Scoped to RK3326 until other platforms verify their key handling.
  if [ "${DEVICE}" = "RK3326" ]; then
    enable_service input.service
  fi
}
