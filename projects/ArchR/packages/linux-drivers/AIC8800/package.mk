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

  # ...then overlay the vendor's own blobs on top. The AveyondFly tree carries
  # an older firmware build: 6 of the 8 files an 8800DC u02 actually loads
  # differ from Tenda's 1.0.1.10 release. Running the manufacturer's firmware
  # under the driver that shipped with it is the right pairing on its own; that
  # is the whole reason, and it is enough. The driver stays AveyondFly's.
  #
  # It does NOT fix the "device descriptor read, error -71". That was the
  # original guess and the 2026-09-04 boot disproved it: the six -71 all land in
  # the re-enumeration after the u-disk to WLAN mode switch, before
  # aic_load_fw_usb even registers, so no firmware byte had reached the chip
  # yet. That fault is in dwc2, not here.
  # See firmware/README.md for provenance and the per-file md5 table.
  cp -a ${PKG_DIR}/firmware/aic8800DC/. ${INSTALL}/$(get_full_firmware_dir)/aic8800DC/

  # Firmware loader must be ready before the WLAN driver probes
  mkdir -p ${INSTALL}/usr/lib/modprobe.d
  cp ${PKG_DIR}/modprobe.d/aic8800-usb.conf ${INSTALL}/usr/lib/modprobe.d/

  # Install AIC8800 USB mode switch script and udev rule
  mkdir -p ${INSTALL}/usr/lib/udev/rules.d
  mkdir -p ${INSTALL}/usr/bin

  # Mode switch script with USB reset fallback
  cat > ${INSTALL}/usr/bin/aic8800-modeswitch << 'SCRIPT'
#!/bin/sh
# AIC8800 USB mode switch: the dongle ships as a u-disk (a69c:5721/5722);
# ejecting it makes it drop off the bus and come back as the WLAN
# function. On the RK3326's dwc2 controller that re-enumeration often
# wedges: the port loops on "device descriptor read, error -71/-110"
# and never recovers on its own. The only thing observed to clear it is
# a full unbind/rebind of the dwc2 platform driver, after which the
# dongle enumerates cleanly in WLAN mode (verified twice on a Soysauce
# with a Tenda AIC8800DC, serial capture 2026-09-03).
DEV="$1"
[ -z "$DEV" ] && exit 0

# The re-enumerated WLAN function is what we wait for - not a wlan
# netdev, which needs the driver to also probe successfully. Any AIC
# vendor ID or a Tenda rebadge on the bus, minus the u-disk PIDs.
wlan_function_present() {
  for d in /sys/bus/usb/devices/*/idVendor; do
    dir=$(dirname "$d")
    vid=$(cat "$d" 2>/dev/null)
    pid=$(cat "$dir/idProduct" 2>/dev/null)
    case "$vid:$pid" in
      a69c:5721|a69c:5722|a69c:5723|a69c:5725|a69c:5726|a69c:5727|a69c:572a|a69c:5730) ;;
      a69c:*|368b:*|2604:*) return 0 ;;
    esac
  done
  return 1
}

# Wait for the WLAN function to enumerate; bail early once it is there
wait_wlan() {
  for i in $(seq 1 "$1"); do
    wlan_function_present && return 0
    sleep 1
  done
  return 1
}

# Eject the mass storage device
eject "/dev/$DEV" 2>/dev/null
wait_wlan 10 && exit 0

# Re-enumeration wedged. Bounce the OTG controller: unbind/rebind the
# dwc2 platform driver so the host port starts from a clean state.
# Exactly one cycle - a second bounce takes the dongle off the bus
# altogether and only a physical replug brings it back.
ctrl=""
for c in /sys/bus/platform/drivers/dwc2/*.usb; do
  [ -e "$c" ] && ctrl=$(basename "$c") && break
done
if [ -n "$ctrl" ]; then
  echo "$ctrl" > /sys/bus/platform/drivers/dwc2/unbind 2>/dev/null
  sleep 2
  echo "$ctrl" > /sys/bus/platform/drivers/dwc2/bind 2>/dev/null
  wait_wlan 12 && exit 0
fi

# Last resort: deauthorize/reauthorize whatever AIC device is left
for usbdev in /sys/bus/usb/devices/*/authorized; do
  dir=$(dirname "$usbdev")
  case "$(cat "$dir/idVendor" 2>/dev/null)" in
    a69c|368b|2604)
      echo 0 > "$usbdev" 2>/dev/null
      sleep 1
      echo 1 > "$usbdev" 2>/dev/null
      break ;;
  esac
done
SCRIPT
  chmod +x ${INSTALL}/usr/bin/aic8800-modeswitch

  # udev rule triggers mode switch script
  # u-disk product IDs taken from the vendor's own aic.rules (Tenda
  # wifi6-adapter-linux-driver V1.0.1.10): 5721 plus the tendaudisk v1-v6
  # rebadges. 5722 is not in the vendor list but is what our field units
  # enumerate as, so it stays.
  cat > ${INSTALL}/usr/lib/udev/rules.d/99-aic8800.rules << 'RULES'
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5721", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5722", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5723", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5725", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5726", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5727", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="572a", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
KERNEL=="sd*", ATTRS{idVendor}=="a69c", ATTRS{idProduct}=="5730", SYMLINK+="aicudisk", RUN+="/usr/bin/aic8800-modeswitch %k"
RULES
}
