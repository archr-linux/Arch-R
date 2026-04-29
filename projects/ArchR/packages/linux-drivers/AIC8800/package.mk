# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

PKG_NAME="AIC8800"
PKG_VERSION="1018f17a629c638acc1a01df19e3f2146e7b4f5c"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/friddle/arch-aic8800-6.12"
PKG_URL="${PKG_SITE}.git"
PKG_LONGDESC="AICsemi AIC8800 USB WiFi+BT driver and firmware"
PKG_TOOLCHAIN="make"
PKG_IS_KERNEL_PKG="yes"

pre_make_target() {
  unset LDFLAGS

  # Switch platform from Ubuntu to manual cross-compilation
  sed -i 's/CONFIG_PLATFORM_UBUNTU ?= y/CONFIG_PLATFORM_UBUNTU ?= n/' \
    ${PKG_BUILD}/drivers/aic8800/Makefile
}

make_target() {
  cd ${PKG_BUILD}/drivers/aic8800
  make V=1 \
       ARCH=${TARGET_KERNEL_ARCH} \
       KDIR=$(kernel_path) \
       CROSS_COMPILE=${TARGET_KERNEL_PREFIX}
}

makeinstall_target() {
  mkdir -p ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/
    find ${PKG_BUILD}/drivers/aic8800 -name "*.ko" \
      -exec cp {} ${INSTALL}/$(get_full_module_dir)/kernel/drivers/net/wireless/ \;

  # Install firmware to kernel-overlays (build system symlinks /usr/lib/firmware there)
  mkdir -p ${INSTALL}/$(get_full_firmware_dir)/aic8800DC
    cp -r ${PKG_BUILD}/fw/aic8800DC/* ${INSTALL}/$(get_full_firmware_dir)/aic8800DC/

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
