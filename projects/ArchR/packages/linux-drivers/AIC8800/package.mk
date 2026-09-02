# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

# Driver source adopted from the AveyondFly fork (field-validated on RK3326
# clones running the same 6.12 kernel); replaces the previous friddle/
# arch-aic8800-6.12 tree. We keep our USB mode-switch handling on top: the
# AIC8800DC ships in u-disk mode (a69c:5721/5722), which the driver's own
# ID table does not cover — without the eject + re-enumeration dance the
# WLAN function never appears.
PKG_NAME="AIC8800"
PKG_VERSION="b6ba4cbacf9657caecce26c2426880c5bb485266"
PKG_SHA256="889aef7279e586bb145dbd891a1f3c1f51139839e3578705760a164e3004a920"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/AveyondFly/aic8800-usb"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="AIC8800 USB WiFi/BT out-of-tree driver (aic_load_fw_usb + aic8800_fdrv_usb)"
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS
}

make_target() {
  kernel_make -C $(kernel_path) M=${PKG_BUILD} modules
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
  cp ${PKG_BUILD}/aic_load_fw/aic_load_fw_usb.ko \
     ${PKG_BUILD}/aic8800_fdrv/aic8800_fdrv_usb.ko \
     ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}

  # Firmware is bundled in the driver repo
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/aic8800DC
  cp -a ${PKG_BUILD}/aic8800DC/. ${INSTALL}/$(get_full_firmware_dir)/aic8800DC/

  # Firmware loader must be ready before the WLAN driver probes
  mkdir -p ${INSTALL}/usr/lib/modprobe.d
  cp ${PKG_DIR}/modprobe.d/aic8800-usb.conf ${INSTALL}/usr/lib/modprobe.d/

  # Install AIC8800 USB mode switch script and udev rule
  mkdir -p ${INSTALL}/usr/lib/udev/rules.d
  mkdir -p ${INSTALL}/usr/bin

  # Mode switch script with USB reset fallback
  cat > ${INSTALL}/usr/bin/aic8800-modeswitch << 'SCRIPT'
#!/bin/sh
# AIC8800 USB mode switch: eject mass storage to activate WiFi mode
# If re-enumeration fails, reset the USB port
DEV="$1"
[ -z "$DEV" ] && exit 0

# Eject the mass storage device
eject "/dev/$DEV" 2>/dev/null

# Wait for WiFi mode to enumerate
for i in $(seq 1 10); do
  sleep 1
  # Check if a wireless interface appeared
  ls /sys/class/net/wlan* >/dev/null 2>&1 && exit 0
done

# If WiFi didn't appear, try resetting the USB bus
for usbdev in /sys/bus/usb/devices/*/authorized; do
  dir=$(dirname "$usbdev")
  if grep -q "a69c" "$dir/idVendor" 2>/dev/null; then
    echo 0 > "$usbdev" 2>/dev/null
    sleep 1
    echo 1 > "$usbdev" 2>/dev/null
    break
  fi
done
SCRIPT
  chmod +x ${INSTALL}/usr/bin/aic8800-modeswitch

  # udev rule triggers mode switch script
  cat > ${INSTALL}/usr/lib/udev/rules.d/99-aic8800.rules << 'RULES'
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5721", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5722", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
RULES
}
