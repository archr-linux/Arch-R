#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-usb-advisor: the build table from a fake module tree
# (modules.alias, a fake modinfo, firmware present or not), then scans of a
# fake sysfs with a working dongle, one without a driver, one missing its
# firmware and a gamepad that must be ignored.
#   bash projects/ArchR/packages/archr/tests/usb_advisor_test.sh

# Checks are eval'd strings: variables are read only there.
# shellcheck disable=SC2016,SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/archr-usb-advisor"
CHIPS="$(dirname "${HERE}")/sources/usb-advisor-chips.tsv"
T=$(mktemp -d)
FAILED=0
trap 'rm -rf "${T}"' EXIT

check() {
  if eval "$2"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    FAILED=1
  fi
}

# --- gen -------------------------------------------------------------------
LIB="${T}/lib"
M="${LIB}/modules/6.12.0"
mkdir -p "${M}/kernel" "${LIB}/firmware/mediatek" "${LIB}/firmware/rtl_bt" "${T}/bin"
for ko in 8188eu rtl8xxxu mt7663u mt7601u btusb btrtl 8821cu; do : >"${M}/kernel/${ko}.ko"; done
cat >"${M}/modules.alias" <<'EOF'
alias usb:v0BDAp0179d*dc*dsc*dp*ic*isc*ip*in* 8188eu
alias usb:v0BDAp0179d*dc*dsc*dp*icFFiscFFipFFin* rtl8xxxu
alias usb:v0E8Dp7663d*dc*dsc*dp*icFFiscFFipFFin* mt7663u
alias usb:v148Fp7601d*dc*dsc*dp*ic*isc*ip*in* mt7601u
alias usb:v*p*d*dcE0dsc01dp01ic*isc*ip*in* btusb
alias usb:v0BDApC811d*dc*dsc*dp*icFFiscFFipFFin* 8821cu
alias pci:v00001234d* notusb
EOF
cat >"${T}/bin/modinfo" <<'EOF'
#!/bin/bash
case "$3" in
  */mt7663u.ko) printf 'mediatek/mt7663pr2h.bin\nmediatek/mt7663_n9_v3.bin\n' ;;
  */mt7601u.ko) echo mt7601u.bin ;;
  */rtl8xxxu.ko) printf 'rtlwifi/rtl8188eufw.bin\nrtlwifi/rtl8723bu_bt.bin\n' ;;
  */btrtl.ko) printf 'rtl_bt/rtl8761b_fw.bin\nrtl_bt/rtl8852bs_fw.bin\n' ;;
esac
EOF
chmod +x "${T}/bin/modinfo"
: >"${LIB}/firmware/mt7601u.bin"
: >"${LIB}/firmware/rtl_bt/rtl8761b_fw.bin"
: >"${LIB}/firmware/rtl_bt/rtl8761b_config.bin"
OUT="${T}/usr/share/archr/usb-advisor.tsv"
PATH="${T}/bin:${PATH}" bash "${SCRIPT}" gen "${LIB}" "${CHIPS}" "${OUT}" 2026-10-30
check "gen dates the table" 'head -n1 "${OUT}" | grep -qx "date	2026-10-30"'
check "two drivers for one ID, one enough" \
  'grep -qx "dev	0bda:0179	Realtek RTL8188ETV	wifi	2.4	8188eu,rtl8xxxu	ok" "${OUT}" ||
   grep -qx "dev	0bda:0179	Realtek RTL8188ETV	wifi	2.4	rtl8xxxu,8188eu	ok" "${OUT}"'
check "missing firmware is named" \
  'grep -qx "dev	0e8d:7663	MediaTek MT7663U	wifi	2.4+5	mt7663u	mediatek/mt7663pr2h.bin,mediatek/mt7663_n9_v3.bin" "${OUT}"'
check "a named ID without a driver" \
  'grep -qx "dev	0bda:b733	Realtek RTL8733BU	wifi+bt	2.4+5	-	-" "${OUT}"'
check "class matches and other buses are skipped" '! grep -q "btusb\|notusb\|1234" "${OUT}"'
check "chips that work, from the files present" \
  '[ "$(grep "^chip" "${OUT}" | cut -f2 | paste -sd/)" = "RTL8821CU/RTL8188FTV / 8188EUS/MT7601U/RTL8761B" ]'

# --- scan ------------------------------------------------------------------
R="${T}/root"
export ARCHR_USB_ROOT="${R}" ARCHR_USB_DMESG="cat ${T}/dmesg"
mkdir -p "${R}/usr/share/archr" "${R}/sys/bus/usb/devices" "${R}/sys/class/net" \
  "${R}/sys/bus/usb/drivers/8188eu" "${R}/sys/bus/usb/drivers/mt7663u" \
  "${R}/sys/bus/usb/drivers/xpad" "${R}/run/archr"
cp "${OUT}" "${R}/usr/share/archr/usb-advisor.tsv"
device() { # name vid pid product class driver
  local d="${R}/sys/devices/usb1/$1"
  mkdir -p "${d}/$1:1.0"
  echo "$2" >"${d}/idVendor"
  echo "$3" >"${d}/idProduct"
  echo "$4" >"${d}/product"
  echo "$5" >"${d}/$1:1.0/bInterfaceClass"
  [ -n "$6" ] && ln -s "../../../../bus/usb/drivers/$6" "${d}/$1:1.0/driver"
  ln -s "../../../devices/usb1/$1" "${R}/sys/bus/usb/devices/$1"
}
device 1-1 0bda 0179 "802.11n NIC" ff 8188eu
mkdir "${R}/sys/class/net/wlan0" "${R}/sys/class/net/lo"
ln -s ../../../devices/usb1/1-1/1-1:1.0 "${R}/sys/class/net/wlan0/device"
echo "[    5.1] mt7663u 1-3:1.0: Direct firmware load for mediatek/mt7663pr2h.bin failed with error -2" >"${T}/dmesg"
bash "${SCRIPT}" scan 0bda:0179
A="${R}/run/archr/usb-advice"
check "a working dongle" \
  'grep -qx "dev	0bda:0179	Realtek RTL8188ETV	wifi	2.4	8188eu,rtl8xxxu	8188eu	wlan0	-	works" "${A}" ||
   grep -qx "dev	0bda:0179	Realtek RTL8188ETV	wifi	2.4	rtl8xxxu,8188eu	8188eu	wlan0	-	works" "${A}"'
check "never seen: announced" 'grep -qx "added	0bda:0179" "${A}" && grep -qx "seq	1" "${A}"'
bash "${SCRIPT}" scan 0bda:0179
check "seen with the same verdict: quiet" '! grep -q "^added" "${A}" && grep -qx "seq	2" "${A}"'

device 1-2 0bda b733 "802.11ac WLAN Adapter" ff ""
device 1-3 0e8d 7663 "Wireless" ff mt7663u
device 1-4 045e 028e "Controller" ff xpad
device 1-5 1234 5678 "Mass Storage" 08 ""
device 1-6 0a12 9999 "x" e0 ""
printf 'Odd\tBT\001\n' >"${R}/sys/devices/usb1/1-6/product"
bash "${SCRIPT}" scan 0bda:b733
check "no driver for the chip" \
  'grep -qx "dev	0bda:b733	Realtek RTL8733BU	wifi+bt	2.4+5	-	-	-	-	no_driver" "${A}" && grep -qx "added	0bda:b733" "${A}"'
check "bound but its firmware failed to load" \
  'grep -q "^dev	0e8d:7663	MediaTek MT7663U	wifi	2.4+5	mt7663u	mt7663u	-	mediatek/mt7663pr2h.bin	firmware$" "${A}"'
check "pads and storage are not adapters" '[ "$(grep -c "^dev" "${A}")" = 4 ]'
check "a device name loses its control characters" \
  'grep -qx "dev	0a12:9999	OddBT	bt	bt	-	-	-	-	no_driver" "${A}"'
S="${R}/storage/.config/archr/usb-seen"
check "seen list, newest scan first" \
  '[ "$(cut -f2 "${S}" | paste -sd" ")" = "0bda:0179 0bda:b733 0e8d:7663 0a12:9999" ]'

rm "${R}/sys/bus/usb/devices/1-2"
bash "${SCRIPT}" scan
check "unplugged: gone from now, kept in seen" \
  '! grep -q "0bda:b733" "${A}" && grep -q "0bda:b733" "${S}" && ! grep -q "^added" "${A}"'
bash "${SCRIPT}" forget 0bda:b733
check "forget drops one adapter" '! grep -q "0bda:b733" "${S}" && grep -q "0bda:0179" "${S}"'
check "the scan holds the lock file" '[ -e "${R}/run/archr/usb-advisor.lock" ]'
check "forget refuses anything but an ID" '! bash "${SCRIPT}" forget "../x" 2>/dev/null'

exit "${FAILED}"
