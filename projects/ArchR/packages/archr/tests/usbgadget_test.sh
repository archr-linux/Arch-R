#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the "internet" mode of usbgadget: a fake tree under
# USBGADGET_ROOT (UDC, carrier, configfs ifname) and fake ip, udhcpc,
# udhcpd, resolvectl and wifictl that record their calls. Covers the
# single-port guard, the Wi-Fi hold and its release on unplug, fallback and
# stop, the lease handling and the status the launcher reads.
#   bash projects/ArchR/packages/archr/tests/usbgadget_test.sh

# Checks are eval'd strings (variables read only there) and the fakes
# expand at run time.
# shellcheck disable=SC2016,SC2317,SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/usbgadget"
T=$(mktemp -d)
FAILED=0
cleanup() {
  [ -f "${T}/pids" ] && xargs -r kill <"${T}/pids" 2>/dev/null
  pkill -f "${SCRIPT} supervise" 2>/dev/null
  rm -rf "${T}"
}
trap cleanup EXIT

export USBGADGET_ROOT="${T}/root" USBGADGET_UNPLUG_GRACE=2
R=${USBGADGET_ROOT}
UDC=ff300000.usb
mkdir -p "${R}/etc/profile.d" "${R}/storage/.cache/usbgadget" "${R}/var/run" \
  "${R}/sys/class/udc/${UDC}/device/usb1/1-0:1.0/usb1-port1" \
  "${R}/sys/kernel/config/usb_gadget/cdc/functions/ncm.usb0" \
  "${R}/sys/class/net/gadget" "${R}/usr/bin" "${R}/usr/sbin" "${T}/bin"
printf 'OS_NAME="ArchR"\nOS_VERSION="20261029"\n' >"${R}/etc/os-release"
echo 0123456789abcdef >"${R}/storage/.cache/systemd-machine-id"
echo gadget >"${R}/sys/kernel/config/usb_gadget/cdc/functions/ncm.usb0/ifname"
: >"${R}/sys/class/udc/${UDC}/function"
echo "get_setting() { cat '${T}/wifi.enabled'; }" >"${R}/etc/profile.d/001-functions"

tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${T}" "$2" >"$1"; chmod +x "$1"; }
tool "${T}/bin/ip" '
echo "ip $*" >>"$T/calls"
case "$*" in
  "-4 address flush dev "*) : >"$T/addr" ;;
  "address replace "*|"address add "*) echo "${3%%/*}" >"$T/addr" ;;
  "-4 -o address show dev "*) [ -s "$T/addr" ] && echo "9: gadget    inet $(cat "$T/addr")/24 scope global gadget" ;;
esac
exit 0'
tool "${T}/bin/resolvectl" 'echo "resolvectl $*" >>"$T/calls"'
tool "${T}/bin/modprobe" 'echo "modprobe $*" >>"$T/calls"'
# Transient units: a named one runs detached and is stopped by name,
# waiting for it as systemd does; a second start of a running one fails.
tool "${T}/bin/systemd-run" '
echo "systemd-run $*" >>"$T/calls"
unit=
while [ "${1#-}" != "$1" ]; do case $1 in --unit=*) unit=${1#--unit=} ;; esac; shift; done
if [ -z "$unit" ]; then "$@" & exit 0; fi
kill -0 "$(cat "$T/unit-$unit" 2>/dev/null)" 2>/dev/null && exit 1
setsid "$@" </dev/null >/dev/null 2>&1 &
echo $! >"$T/unit-$unit"; echo $! >>"$T/pids"'
tool "${T}/bin/systemctl" '
echo "systemctl $*" >>"$T/calls"
[ "$1" = is-active ] && { kill -0 "$(cat "$T/unit-$3" 2>/dev/null)" 2>/dev/null; exit; }
[ "$1" = stop ] || exit 0
pid=$(cat "$T/unit-$2" 2>/dev/null) || exit 0
kill "$pid" 2>/dev/null
while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
rm -f "$T/unit-$2"'
tool "${T}/bin/udevadm" ':'
tool "${R}/usr/bin/wifictl" 'echo "wifictl $*" >>"$T/calls"'
# A lease from $T/lease (lines of env assignments), or no answer at all.
tool "${R}/usr/sbin/udhcpc" '
echo "udhcpc $*" >>"$T/calls"
while [ $# -gt 0 ]; do case $1 in -s) s=$2; shift ;; -p) p=$2; shift ;; esac; shift; done
echo $$ >"$p"; echo $$ >>"$T/pids"
[ -s "$T/lease" ] || { sleep 1; exit 1; }
env $(cat "$T/lease") "$s" bound
# The PC stops sharing: the lease ends and udhcpc -n gives up.
if [ -e "$T/lose" ]; then sleep 1; env interface=gadget "$s" deconfig; exit 1; fi
exec sleep 600'
tool "${R}/usr/sbin/udhcpd" '
echo "udhcpd $*" >>"$T/calls"
pid=$(awk "\$1 == \"pidfile\" { print \$2 }" "$2")
sleep 600 & echo $! >"$pid"; echo $! >>"$T/pids"'
export PATH="${T}/bin:${PATH}"

ok() { echo "ok: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
# Polls a condition: the supervisor reacts within about a second.
wait_for() {
  for _ in $(seq 50); do eval "$2" && { ok "$1"; return; }; sleep 0.2; done
  fail "$1 (link file: $(cat "${R}/run/usbgadget/link" 2>/dev/null), status: $(field link))"
}
gadget() { "${SCRIPT}" "$@"; }
field() { gadget status 2>/dev/null | sed -n "s/^$1=//p"; }
calls() { grep -c "$1" "${T}/calls" 2>/dev/null; }
carrier() { echo "$1" >"${R}/sys/class/net/gadget/carrier"; }
# What the supervisor has seen; status reads the carrier itself.
seen() { [ "$(cat "${R}/run/usbgadget/link" 2>/dev/null)" = "$1" ]; }
LEASE='interface=gadget ip=192.168.137.42 subnet=255.255.255.0 router=192.168.137.1 dns=192.168.137.1'

: >"${T}/calls"
echo 1 >"${T}/wifi.enabled"
carrier 0

check "options list internet" '[ "$(gadget --options)" = "disabled network internet file_transfer" ]'

# The single OTG port hosts a device: refused before anything changes.
echo configured >"${R}/sys/class/udc/${UDC}/device/usb1/1-0:1.0/usb1-port1/state"
gadget internet >/dev/null 2>&1
check "busy port exits 3" '[ $? = 3 ]'
check "busy port keeps the state file" '[ ! -e "${R}/storage/.cache/usbgadget/usbgadget.conf" ]'
echo "not attached" >"${R}/sys/class/udc/${UDC}/device/usb1/1-0:1.0/usb1-port1/state"

# Internet mode bound to the UDC, as usb_start leaves it.
echo cdc >"${R}/sys/class/udc/${UDC}/function"
printf 'USB_MODE=cdc\nUSB_NET=internet\nUSB_RNDIS=0\n' >"${R}/storage/.cache/usbgadget/usbgadget.conf"
check "current mode is internet" '[ "$(gadget)" = internet ]'
loaded=$(calls modprobe)
gadget status >/dev/null; gadget address >/dev/null 2>&1; gadget --options >/dev/null
check "queries load no modules" '[ "$(calls modprobe)" = "${loaded}" ]'
check "compatibility off by default" '[ "$(gadget compat)" = 0 ] && [ "$(field compat)" = 0 ]'
gadget compat 2 >/dev/null 2>&1
check "compatibility rejects other values" '[ $? = 2 ]'
systemd-run --unit=usbgadget-internet "${SCRIPT}" supervise

wait_for "no cable: waiting" '[ "$(field link)" = waiting ]'
check "no cable: Wi-Fi untouched" '[ "$(calls wifictl)" = 0 ] && [ "$(field wifi)" = free ]'

echo "${LEASE}" >"${T}/lease"
carrier 1
wait_for "lease: online" '[ "$(field link)" = online ]'
check "lease: address from the PC" '[ "$(field address)" = 192.168.137.42 ]'
check "lease: Wi-Fi held off" '[ "$(field wifi)" = held ] && [ "$(calls "wifictl disable")" = 1 ]'
check "lease: default route through the PC" 'grep -q "route replace default via 192.168.137.1 dev gadget metric 100" "${T}/calls"'
check "lease: DNS to resolved, not resolv.conf" 'grep -q "resolvectl dns gadget 192.168.137.1" "${T}/calls"'
check "lease: no local DHCP server" '[ "$(calls "udhcpd ")" = 0 ]'

carrier 0
wait_for "unplugged: waiting" 'seen waiting && [ "$(field link)" = waiting ]'
wait_for "unplugged: Wi-Fi back on and reconnecting" \
  '[ "$(field wifi)" = free ] && [ "$(calls "wifictl enable")" = 1 ] && [ "$(calls "^wifictl connect")" = 1 ]'
check "unplugged: DNS reverted" 'grep -q "resolvectl revert gadget" "${T}/calls"'
check "unplugged: no address left" '[ -z "$(field address)" ]'

# The PC does not share: fixed address and Wi-Fi back.
: >"${T}/lease"
carrier 1
wait_for "no sharing: falls back to the network mode" '[ "$(field link)" = fallback ]'
check "no sharing: fixed address" '[ "$(field address)" = 169.254.170.2 ]'
check "no sharing: local DHCP server" '[ "$(calls "udhcpd -S")" = 1 ]'
check "no sharing: Wi-Fi stays off while the PC is there" \
  '[ "$(field wifi)" = held ] && [ "$(calls "wifictl enable")" = 1 ]'

# Plugged again with sharing on, and the user had Wi-Fi off: it stays off.
carrier 0
wait_for "unplugged after no sharing: Wi-Fi back" \
  'seen waiting && [ "$(field wifi)" = free ] && [ "$(calls "wifictl enable")" = 2 ]'
echo 0 >"${T}/wifi.enabled"
echo "${LEASE}" >"${T}/lease"
carrier 1
wait_for "replug: online" '[ "$(field link)" = online ]'

# The PC stops sharing while connected: a lost lease falls back too.
carrier 0
wait_for "lease lost: unplugged first" 'seen waiting'
touch "${T}/lose"
carrier 1
wait_for "lease lost: falls back to the network mode" '[ "$(field link)" = fallback ]'
check "lease lost: fixed address" '[ "$(field address)" = 169.254.170.2 ]'
rm -f "${T}/lose"

# Leaving the mode stops the supervisor and gives Wi-Fi back as it was.
gadget disabled >/dev/null 2>&1
wait_for "disabled: supervisor gone" '! pgrep -f "${SCRIPT} supervise" >/dev/null'
check "disabled: Wi-Fi not held" '[ ! -e "${R}/run/usbgadget/wifi-held" ]'
check "disabled: Wi-Fi off stays off" '[ "$(calls "wifictl enable")" = 2 ]'
check "disabled: state file keeps the net choice" \
  'grep -qx USB_MODE=disabled "${R}/storage/.cache/usbgadget/usbgadget.conf" && grep -qx USB_NET=internet "${R}/storage/.cache/usbgadget/usbgadget.conf"'

# A lease without a gateway is a local link, not internet.
env interface=gadget ip=10.42.0.5 subnet=255.255.255.0 "${SCRIPT}" bound
check "lease without gateway: local" '[ "$(cat "${R}/run/usbgadget/link")" = local ]'

# The whole flow through the commands: configfs comes from fake mkdir and
# rmdir (attributes appear with their directory, a name in $T/no-<func>
# refuses that function). The UDC is renamed "cdc" so that its function
# file can be a link to the gadget's UDC file: binding writes the UDC name
# there, and the kernel's at-once "cdc" in the function file follows.
tool "${T}/bin/mkdir" '
for d; do
  case $d in -*) continue ;; esac
  /usr/bin/mkdir -p "$d" || exit 1
  case $d in
    */usb_gadget/cdc|*/usb_gadget/mtp)
      /usr/bin/mkdir -p "$d/strings" "$d/configs" "$d/functions" "$d/os_desc"; : >"$d/UDC" ;;
    */configs/c.1) /usr/bin/mkdir -p "$d/strings" ;;
    */functions/ncm.usb0|*/functions/rndis.usb0)
      f=${d##*/}; f=${f%.usb0}
      [ -e "$T/no-$f" ] && { rm -r "$d"; exit 1; }
      /usr/bin/mkdir -p "$d/os_desc/interface.$f"; echo gadget >"$d/ifname" ;;
  esac
done'
tool "${T}/bin/rmdir" 'rm -r "$@"'
CFG="${R}/sys/kernel/config/usb_gadget"
rm -f "${R}/storage/.cache/usbgadget/usbgadget.conf"
mv "${R}/sys/class/udc/${UDC}" "${R}/sys/class/udc/cdc"
UDC=cdc
ln -sf "${CFG}/cdc/UDC" "${R}/sys/class/udc/cdc/function"
echo 1 >"${T}/wifi.enabled"
echo "${LEASE}" >"${T}/lease"
carrier 1
unit_up() { kill -0 "$(cat "${T}/unit-usbgadget-internet" 2>/dev/null)" 2>/dev/null; }

gadget prepare >/dev/null 2>&1
check "prepare: NCM with its OS descriptor served" \
  '[ -d "${CFG}/cdc/functions/ncm.usb0" ] && [ -L "${CFG}/cdc/os_desc/c.1" ] && [ "$(cat "${CFG}/cdc/functions/ncm.usb0/os_desc/interface.ncm/compatible_id")" = WINNCM ]'

gadget network >/dev/null 2>&1
check "network: started" '[ $? = 0 ]'
wait_for "network: fixed address, no supervisor" \
  '[ "$(field mode)" = network ] && [ "$(field link)" = local ] && [ "$(field address)" = 169.254.170.2 ] && ! unit_up'
udhcpd=$(cat "${R}/var/run/udhcpd.pid")

gadget internet >/dev/null 2>&1
check "network to internet: supervisor launched as a unit" 'grep -q "systemd-run .*--unit=usbgadget-internet .* supervise" "${T}/calls"'
wait_for "network to internet: online, Wi-Fi held" '[ "$(field link)" = online ] && [ "$(field wifi)" = held ]'
check "network to internet: local DHCP server stopped" '! kill -0 "${udhcpd}" 2>/dev/null'

offs=$(calls "wifictl disable"); ons=$(calls "wifictl enable")
gadget compat 1 >/dev/null 2>&1
check "compat on: done" '[ $? = 0 ]'
check "compat on: RNDIS gadget" \
  '[ -d "${CFG}/cdc/functions/rndis.usb0" ] && [ ! -d "${CFG}/cdc/functions/ncm.usb0" ] && [ "$(cat "${CFG}/cdc/bDeviceClass")" = 0xEF ] && [ "$(cat "${CFG}/cdc/functions/rndis.usb0/os_desc/interface.rndis/compatible_id")" = RNDIS ]'
wait_for "compat on: internet again, compat reported" '[ "$(field link)" = online ] && [ "$(field compat)" = 1 ] && unit_up'
check "compat on: Wi-Fi never toggled" \
  '[ "$(calls "wifictl disable")" = "${offs}" ] && [ "$(calls "wifictl enable")" = "${ons}" ] && [ "$(field wifi)" = held ]'

touch "${T}/no-ncm" "${T}/no-rndis"
gadget compat 0 >/dev/null 2>&1
check "compat with no gadget possible: exit 4" '[ $? = 4 ]'
check "compat with no gadget possible: function off" \
  'grep -qx USB_MODE=disabled "${R}/storage/.cache/usbgadget/usbgadget.conf" && [ ! -d "${CFG}/cdc" ] && ! unit_up'
wait_for "compat with no gadget possible: Wi-Fi back" '[ "$(field wifi)" = free ] && [ "$(calls "wifictl enable")" = $((ons + 1)) ]'
rm -f "${T}/no-ncm" "${T}/no-rndis"

gadget compat 0 >/dev/null 2>&1
check "compat off while off: NCM rebuilt" '[ $? = 0 ] && [ -d "${CFG}/cdc/functions/ncm.usb0" ]'
gadget internet >/dev/null 2>&1
wait_for "internet again: online" '[ "$(field link)" = online ] && [ "$(field wifi)" = held ]'

# Two stops at once: one release of Wi-Fi, nothing left running.
ons=$(calls "wifictl enable")
gadget disabled >/dev/null 2>&1 &
first=$!
gadget disabled >/dev/null 2>&1 &
wait "${first}" "$!"
check "concurrent stop: supervisor gone" '! unit_up && ! pgrep -f "${SCRIPT} supervise" >/dev/null'
check "concurrent stop: Wi-Fi released once" '[ "$(field wifi)" = free ] && [ "$(calls "wifictl enable")" = $((ons + 1)) ]'
wait_for "concurrent stop: function off" '[ "$(field mode)" = disabled ]'

exit "${FAILED}"
