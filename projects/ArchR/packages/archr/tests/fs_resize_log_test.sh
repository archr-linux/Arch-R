#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the first-boot log of fs-resize. /flash/fs-resize.log is
# the one trace a user can read on a PC when the first boot hangs, so every
# step must reach the card (sync -f on the boot FAT) before it runs and
# with its real exit status after. Without that, a kernel hang loses the
# last ~30 s of the log (vfat writeback) and the log says nothing about
# where it stopped. Kernel errors must also reach the screen during the
# resize, and the first boot must always end in a restart.
#
# The real fs-resize, functions and roms-partition run with their absolute
# paths moved under a temp dir and fake tools on PATH; no root, no devices.
# The sysrq fallback writes to SYSRQ_TRIGGER, a file here.
#   bash projects/ArchR/packages/archr/tests/fs_resize_log_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BB="$(cd "${HERE}/../.." && pwd)/sysutils/busybox/scripts"
T=$(mktemp -d)
FAILED=0
ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# Never the host's /proc/sysrq-trigger.
export SYSRQ_TRIGGER="${T}/sysrq-trigger"

# Runs left behind (a hang, a reboot() that never returns) go in their own
# process group and are killed whole, with every sleep they started.
RPGID=
stop_run() {
  [ -n "${RPGID}" ] || return 0
  kill -KILL -- "-${RPGID}" 2>/dev/null
  wait 2>/dev/null
}
strays() { pgrep -g "${RPGID}" >/dev/null 2>&1; }
trap 'stop_run; [ -n "${KEEP:-}" ] || rm -rf "${T}"' EXIT

setup() {
  rm -rf "${T:?}"/{root,bin,calls,sysrq-trigger}
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
  for t in umount reboot mkfs.exfat fsck.exfat udevadm; do
    tool "$t" "echo \"$t \$*\" >>\"\$T/calls\""
  done
  # Exit codes set per case.
  tool e2fsck 'echo "e2fsck $*" >>"$T/calls"; exit "${FSCK_RC:-0}"'
  tool tune2fs 'echo "tune2fs $*" >>"$T/calls"; exit "${TUNE_RC:-0}"'
  tool fatlabel 'echo "fatlabel $*" >>"$T/calls"; exit "${FAT_RC:-0}"'
  # HANG_ROOT_RO: remounting / read-only never returns (stuck I/O).
  tool mount '
echo "mount $*" >>"$T/calls"
if [ -n "${HANG_ROOT_RO:-}" ] && [ "$*" = "-o remount,ro /" ]; then exec sleep 300; fi'
  tool usleep 'sleep 0.05'
  tool dmesg 'echo "[  9.000] mmc0: stub kernel line"'
  tool blkid 'exit 0'
  printf '#!/bin/bash\necho "resize2fs $*" >>%s/calls\n' "${T}" >"${T}/bin/resize2fs"
  chmod +x "${T}/bin/resize2fs"
  # sync records how many lines of the log were on the card at that point.
  tool sync "echo \"sync \$* \$(wc -l <\"${R}/flash/fs-resize.log\" 2>/dev/null)\" >>\"\$T/calls\""
  tool parted '
case "$*" in
  *print*) printf "BYT;\n/dev/mmcblk0:125042688s:sd/mmc:512:512:msdos:SD:;\n"
           printf "1:32768s:557055s:524288s:fat32::boot;\n2:557056s:9994239s:9437184s:::;\n3:9994240s:10059775s:65536s:ext4::;\n" ;;
  *) echo "parted $*" >>"$T/calls" ;;
esac'
}
LOG() { cat "${R}/flash/fs-resize.log" 2>/dev/null; }
# Line number of the first call matching the regex $1 (empty if none).
call_at() { grep -n -E "$1" "${T}/calls" | head -1 | cut -d: -f1; }
before() { local a b; a=$(call_at "$1"); b=$(call_at "$2"); [ -n "${a}" ] && [ -n "${b}" ] && [ "${a}" -lt "${b}" ]; }
# The status logged for the step whose line matches $1.
step_status() { LOG | grep -A1 -E "^\*\*\* \[[0-9.]+\] $1" | sed -n 's/^    \[[0-9.]*\] exit //p' | head -1; }
# Runs fs-resize in its own process group (setsid); waits until it is one.
start_run() {
  setsid env PATH="${T}/bin:${PATH}" "$@" bash "${R}/lib/fs-resize" >"${T}/out" 2>&1 </dev/null &
  RPGID=$!
  for _ in $(seq 1 50); do
    [ "$(ps -o pgid= -p "${RPGID}" 2>/dev/null | tr -d ' ')" = "${RPGID}" ] && return 0
    sleep 0.02
  done
  RPGID=
  fail "could not start fs-resize in its own process group"
  exit 1
}
run() { env PATH="${T}/bin:${PATH}" RESTART_WAIT=0 "$@" timeout 60 bash "${R}/lib/fs-resize" >"${T}/out" 2>&1 </dev/null; }
no_host_sysrq() { [ ! -e "${R}/proc/sysrq-trigger" ]; }

### 1. A resize2fs that never returns, as on the devices that hang.
setup
printf '#!/bin/bash\ntouch %s/resize2fs.started\nexec sleep 300\n' "${T}" >"${T}/bin/resize2fs"
start_run
for _ in $(seq 1 100); do [ -e "${T}/resize2fs.started" ] && break; sleep 0.1; done
check "hang: resize2fs was reached" '[ -e "${T}/resize2fs.started" ]'
N=$(grep -n "resize2fs" "${R}/flash/fs-resize.log" | head -1 | cut -d: -f1)
check "hang: the log names the step that is running" '[ -n "${N}" ]'
# The last sync of the boot FAT must already cover the resize2fs line.
LAST=$(grep "^sync -f" "${T}/calls" | tail -1 | awk '{print $NF}')
check "hang: that line is synced to the card (sync -f covers line ${N:-?}, last sync saw ${LAST:-none})" \
  '[ -n "${LAST}" ] && [ -n "${N}" ] && [ "${LAST}" -ge "${N}" ]'
check "hang: the steps before it logged their exit status" \
  '[ "$(step_status "(check_fs|e2fsck)")" = 0 ]'
check "hang: kernel errors are shown on the console during the resize" \
  '[ "$(cat "${R}/proc/sys/kernel/printk")" = "4 4 1 7" ]'
stop_run
check "hang: nothing of the run is left (its sleep 300 neither)" '! strays'
RPGID=

### 2. A normal first boot still completes and returns the console quiet.
setup
run
check "normal: resize2fs ran on the STORAGE partition" 'grep -q "^resize2fs /dev/mmcblk0p3" "${T}/calls"'
check "normal: reboots at the end, straight through reboot() (-ff)" 'grep -q "^reboot -ff$" "${T}/calls"'
check "normal: the log says the restart was reached, after the sync" \
  'LOG | tail -1 | grep -q "restarting" && LOG | grep -A1 "^\*\*\* .*\] sync" | grep -q "exit 0"'
check "normal: /flash is read-only again before the restart" \
  '[ "$(grep -n "remount,ro .*flash" "${T}/calls" | tail -1 | cut -d: -f1)" -lt "$(call_at "^reboot")" ]'
check "normal: / is remounted read-only before the restart" 'before "^mount -o remount,ro /$" "^reboot"'
check "normal: the boot trace stays opt-in (no /flash/archr-trace)" '[ ! -e "${R}/flash/archr-trace" ]'
check "normal: kernel messages of the run land in the log" 'LOG | grep -q "stub kernel line"'
check "normal: console log level restored" '[ "$(cat "${R}/proc/sys/kernel/printk")" = "1 4 1 7" ]'
check "normal: steps carry the uptime they started at" 'LOG | grep -q "^\*\*\* \[12.34\] resize2fs"'
check "normal: every step logged an exit status" \
  '[ "$(LOG | grep -c "^\*\*\* ")" -gt 0 ] && [ "$(LOG | grep -c "^\*\*\* ")" = "$(LOG | grep -c "exit [0-9]")" ]'
check "normal: fsck and new UUIDs logged as succeeded" '[ "$(step_status "(check_fs|e2fsck)")" = 0 ] && [ "$(step_status "(new_ids|tune2fs)")" = 0 ]'
check "normal: the sysrq fallback goes to SYSRQ_TRIGGER (sync, remount, boot), never to /proc" \
  '[ "$(cat "${SYSRQ_TRIGGER}" 2>/dev/null)" = b ] && no_host_sysrq'

### 3. reboot() never returns (a driver stuck in its shutdown hook): the
### board must still restart, without the device shutdown.
setup
printf '#!/bin/bash\necho "reboot $*" >>%s/calls\nexec sleep 300\n' "${T}" >"${T}/bin/reboot"
start_run RESTART_WAIT=1
for _ in $(seq 1 150); do [ -s "${SYSRQ_TRIGGER}" ] && [ "$(cat "${SYSRQ_TRIGGER}")" = b ] && break; sleep 0.1; done
check "stuck reboot: emergency restart requested (sysrq b) on SYSRQ_TRIGGER" '[ "$(cat "${SYSRQ_TRIGGER}" 2>/dev/null)" = b ]'
check "stuck reboot: the host's sysrq-trigger path was never written" 'no_host_sysrq'
stop_run
check "stuck reboot: nothing of the run is left" '! strays'
RPGID=

### 4. Real step status: e2fsck finds unfixed errors (4), then UUIDs fail.
setup
run FSCK_RC=4 TUNE_RC=3
check "fsck fails: the step logs exit 4, not 0" '[ "$(step_status "(check_fs|e2fsck)")" = 4 ]'
check "fsck fails: roms_create failed here (no partition 4 appears), the fallback is taken" \
  'LOG | grep -q "ROMs partition failed; falling back to the old layout"'
check "fsck fails: the fallback does not grow the broken filesystem either (no resize2fs at all)" \
  '! grep -q "^resize2fs" "${T}/calls" && LOG | grep -q "e2fsck exited 4; skipping resize2fs after the fallback too"'
check "fsck fails: the resize right after it is skipped" \
  'LOG | grep -A2 -E "^\*\*\* \[[0-9.]+\] (check_fs|e2fsck)" | grep -q "e2fsck exited 4; skipping resize2fs"'
check "tune2fs fails: the UUID step logs its status (3), fatlabel still ran" \
  '[ "$(step_status "(new_ids|tune2fs)")" = 3 ] && grep -q "^fatlabel" "${T}/calls"'
check "fsck fails: still restarts" 'grep -q "^reboot -ff$" "${T}/calls"'
setup
run FAT_RC=2
check "fatlabel alone fails: the UUID step logs exit 2" '[ "$(step_status "(new_ids|tune2fs)")" = 2 ]'

### 5. A card already set up (STORAGE still mounted): put away, restart.
setup
mkdir -p "${R}/storage/.config"
run
check "initialised: refused and logged" 'LOG | grep -q "Resizing is not permitted"'
check "initialised: STORAGE unmounted before the restart" 'before "^umount .*storage" "^reboot -ff"'
check "initialised: / and /flash read-only before the restart" \
  'before "^mount -o remount,ro /$" "^reboot -ff" && [ "$(grep -n "remount,ro .*flash" "${T}/calls" | tail -1 | cut -d: -f1)" -lt "$(call_at "^reboot")" ]'
check "initialised: no resize even if reboot() returned" '! grep -q "^parted\|^resize2fs\|^e2fsck" "${T}/calls"'

### 6. Putting / away hangs: the sysrq timer, started first, still fires.
setup
start_run RESTART_WAIT=1 HANG_ROOT_RO=1
for _ in $(seq 1 150); do [ -s "${SYSRQ_TRIGGER}" ] && [ "$(cat "${SYSRQ_TRIGGER}")" = b ] && break; sleep 0.1; done
check "stuck remount: emergency restart still requested" '[ "$(cat "${SYSRQ_TRIGGER}" 2>/dev/null)" = b ] && no_host_sysrq'
stop_run
check "stuck remount: nothing of the run is left" '! strays'
RPGID=

exit "${FAILED}"
