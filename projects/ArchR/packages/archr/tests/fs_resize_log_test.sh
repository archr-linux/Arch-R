#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the first-boot log of fs-resize. /flash/fs-resize.log is
# the one trace a user can read on a PC when the first boot hangs, so every
# step must reach the card (sync -f on the boot FAT) before it runs and
# with its exit status after. Without that, a kernel hang loses the last
# ~30 s of the log (vfat writeback) and the log says nothing about where it
# stopped. Kernel errors must also reach the screen during the resize.
#
# The real fs-resize, functions and roms-partition run with their absolute
# paths moved under a temp dir and fake tools on PATH; no root, no devices.
#   bash projects/ArchR/packages/archr/tests/fs_resize_log_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BB="$(cd "${HERE}/../.." && pwd)/sysutils/busybox/scripts"
T=$(mktemp -d)
trap 'kill "${RPID:-}" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "${T}"' EXIT
FAILED=0
ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

setup() {
  rm -rf "${T:?}"/{root,bin,calls}
  R="${T}/root"
  mkdir -p "${R}"/{storage,flash,lib,tmp,dev,proc/sys/kernel} "${T}/bin"
  : >"${R}/storage/.please_resize_me"
  echo "1 4 1 7" >"${R}/proc/sys/kernel/printk"
  echo "12.34 40.00" >"${R}/proc/uptime"
  # A 64 GB card: STORAGE is mmcblk0p3, so the ROMs layout is planned.
  echo "/dev/mmcblk0p3 ${R}/storage ext4 rw,noatime 0 0" >"${R}/proc/mounts"
  local p
  for f in fs-resize functions roms-partition; do
    # /tmp/ first: the paths inserted after it may live under /tmp.
    p=$(sed -e "s#/tmp/#${R}/tmp/#g" -e "s#/usr/lib/archr/#${R}/lib/#g" \
      -e "s#/storage#${R}/storage#g" -e "s#/flash#${R}/flash#g" \
      -e "s#/proc/#${R}/proc/#g" -e "s#/dev/\.progress#${R}/dev/.progress#g" \
      -e "s/@DISTRONAME@/ArchR/g" "${BB}/${f}")
    printf '%s\n' "${p}" >"${R}/lib/${f}"
  done
  chmod +x "${R}/lib/fs-resize"
  tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${T}" "$2" >"${T}/bin/$1"; chmod +x "${T}/bin/$1"; }
  for t in mount umount tune2fs fatlabel reboot mkfs.exfat fsck.exfat udevadm e2fsck; do
    tool "$t" "echo \"$t \$*\" >>\"\$T/calls\""
  done
  tool usleep 'sleep 0.05'
  tool dmesg 'echo "[  9.000] mmc0: stub kernel line"'
  tool blkid 'exit 0'
  # sync records how many lines of the log were on the card at that point.
  tool sync "echo \"sync \$* \$(wc -l <\"${R}/flash/fs-resize.log\" 2>/dev/null)\" >>\"\$T/calls\""
  tool parted '
case "$*" in
  *print*) printf "BYT;\n/dev/mmcblk0:125042688s:sd/mmc:512:512:msdos:SD:;\n"
           printf "1:32768s:557055s:524288s:fat32::boot;\n2:557056s:9994239s:9437184s:::;\n3:9994240s:10059775s:65536s:ext4::;\n" ;;
  *) echo "parted $*" >>"$T/calls" ;;
esac'
  command -v mkfs.exfat >/dev/null || true
}
LOG() { cat "${R}/flash/fs-resize.log" 2>/dev/null; }

### 1. A resize2fs that never returns, as on the devices that hang.
setup
printf '#!/bin/bash\ntouch %s/resize2fs.started\nexec sleep 300\n' "${T}" >"${T}/bin/resize2fs"
chmod +x "${T}/bin/resize2fs"
PATH="${T}/bin:${PATH}" bash "${R}/lib/fs-resize" >"${T}/out" 2>&1 </dev/null &
RPID=$!
for _ in $(seq 1 100); do [ -e "${T}/resize2fs.started" ] && break; sleep 0.1; done
check "hang: resize2fs was reached" '[ -e "${T}/resize2fs.started" ]'
N=$(grep -n "resize2fs" "${R}/flash/fs-resize.log" | head -1 | cut -d: -f1)
check "hang: the log names the step that is running" '[ -n "${N}" ]'
# The last sync of the boot FAT must already cover the resize2fs line.
LAST=$(grep "^sync -f" "${T}/calls" | tail -1 | awk '{print $NF}')
check "hang: that line is synced to the card (sync -f covers line ${N:-?}, last sync saw ${LAST:-none})" \
  '[ -n "${LAST}" ] && [ -n "${N}" ] && [ "${LAST}" -ge "${N}" ]'
check "hang: the steps before it logged their exit status" \
  'grep -q "e2fsck.*" <(LOG) && LOG | grep -q "exit 0"'
check "hang: kernel errors are shown on the console during the resize" \
  '[ "$(cat "${R}/proc/sys/kernel/printk")" = "4 4 1 7" ]'
kill "${RPID}" 2>/dev/null; wait "${RPID}" 2>/dev/null; RPID=

### 2. A normal first boot still completes and returns the console quiet.
setup
printf '#!/bin/bash\necho "resize2fs $*" >>%s/calls\n' "${T}" >"${T}/bin/resize2fs"
chmod +x "${T}/bin/resize2fs"
PATH="${T}/bin:${PATH}" timeout 60 bash "${R}/lib/fs-resize" >"${T}/out" 2>&1 </dev/null
check "normal: resize2fs ran on the STORAGE partition" 'grep -q "^resize2fs /dev/mmcblk0p3" "${T}/calls"'
check "normal: reboots at the end" 'grep -q "^reboot" "${T}/calls"'
check "normal: kernel messages of the run land in the log" 'LOG | grep -q "stub kernel line"'
check "normal: console log level restored" '[ "$(cat "${R}/proc/sys/kernel/printk")" = "1 4 1 7" ]'
check "normal: steps carry the uptime they started at" 'LOG | grep -q "^\*\*\* \[12.34\] resize2fs"'
check "normal: every step logged an exit status" \
  '[ "$(LOG | grep -c "^\*\*\* ")" -gt 0 ] && [ "$(LOG | grep -c "^\*\*\* ")" = "$(LOG | grep -c "exit [0-9]")" ]'

exit "${FAILED}"
