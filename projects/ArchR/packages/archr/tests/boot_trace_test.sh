#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the boot trace on /flash: boot_trace in the initramfs
# (scripts/init) and archr-boot-trace under systemd. A boot stuck on a
# frozen screen must leave, on the one partition a PC reads, the step it
# reached, what systemd still waits for and what is stuck in the kernel.
# Fake tools on PATH; no root, no devices. A read-only /flash is a folder
# without write permission (so the test must not run as root), and
# /proc/mounts and /dev/kmsg are files here.
#   bash projects/ArchR/packages/archr/tests/boot_trace_test.sh

set -u
[ "$(id -u)" != 0 ] || { echo "run as a normal user: a read-only /flash is simulated with permissions"; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
PKGS="$(cd "${HERE}/../.." && pwd)"
SCRIPT="${PKGS}/archr/sources/scripts/archr-boot-trace"
INIT="${PKGS}/sysutils/busybox/scripts/init"
QUIRK="${PKGS}/hardware/quirks/devices/Generic EE clone/002-generate_dtbo"
T=$(mktemp -d)
HOLDER=
trap '[ -n "${HOLDER}" ] && kill "${HOLDER}" 2>/dev/null; chmod -R u+w "${T}" 2>/dev/null; [ -n "${KEEP:-}" ] || rm -rf "${T}"' EXIT
FAILED=0
ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

setup() {
  chmod -R u+w "${T}" 2>/dev/null
  rm -rf "${T:?}"/{flash,bin,run,calls,state,mounts,kmsg,flake,lock}
  mkdir -p "${T}/flash" "${T}/bin" "${T}/run"
  echo 0 >"${T}/state"
  tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${T}" "$2" >"${T}/bin/$1"; chmod +x "${T}/bin/$1"; }
  # /flash as mounted: its options in $T/mounts, its permissions to match.
  # With $T/flake, the next remount rw is undone at once, as if another
  # writer had remounted /flash read-only right after it.
  tool mount '
echo "mount $*" >>"$T/calls"
case "$*" in
  "-o remount,rw $T/flash")
    if [ -e "$T/flake" ]; then rm -f "$T/flake"; exit 0; fi
    sed -i "s# ro,# rw,#" "$T/mounts"; chmod -R u+w "$T/flash" ;;
  "-o remount,ro $T/flash")
    sed -i "s# rw,# ro,#" "$T/mounts"; chmod -R a-w "$T/flash" ;;
esac'
  tool sync 'echo "sync $*" >>"$T/calls"'
  tool sleep ':'
  tool journalctl 'echo "journal: warning line"'
  # Each call of is-system-running moves the boot on and adds a kernel
  # record. WRAP: the ring buffer keeps only the last two. QUIRK_AT: the
  # clone quirk remounts /flash read-only at that call.
  tool systemctl '
case "$1" in
  is-system-running)
    n=$(($(cat "$T/state") + 1)); echo $n >"$T/state"
    lo=1; [ -n "${WRAP:-}" ] && [ $n -gt 2 ] && lo=$((n - 1))
    : >"$T/kmsg"
    for i in $(seq $lo $n); do printf "6,%d,%d000000,-;kernel line %d\n SUBSYSTEM=x\n" $i $i $i >>"$T/kmsg"; done
    [ "${QUIRK_AT:-0}" = $n ] && "$T/bin/mount" -o remount,ro "$T/flash"
    if [ -n "${STUCK:-}" ] || [ $n -lt 3 ]; then echo starting; else echo running; fi ;;
  list-jobs) echo "42 sway.service start waiting" ;;
  is-active) echo active; echo activating ;;
  --failed) echo "x.service failed" ;;
esac'
  # The same records, as dmesg prints them.
  tool dmesg 'sed -n "s/^6,\([0-9]*\),[0-9]*,-;\(.*\)/[ \1.0] \2/p" "$T/kmsg" 2>/dev/null'
  tool ps 'echo "S 1 ep_poll /sbin/init"; echo "D 77 mmc_wait_for_req resize2fs"'
  echo "common:/usr/lib/autostart/common/006-display" >"${T}/step"
  # /flash starts read-only, as the boot leaves it.
  echo "/dev/mmcblk0p1 ${T}/flash vfat ro,relatime 0 0" >"${T}/mounts"
  chmod a-w "${T}/flash"
}
mark() { chmod u+w "${T}/flash"; : >"${T}/flash/archr-trace"; chmod a-w "${T}/flash" "${T}/flash/archr-trace"; }
LOG() { cat "${T}/flash/boot-trace.log" 2>/dev/null; }
size() { stat -c %s "$1" 2>/dev/null || echo 0; }
each_once() { local i; for i in "$@"; do [ "$(LOG | grep -c "kernel line ${i}$")" = 1 ] || return 1; done; }
flash_is_ro() { grep -q " ro," "${T}/mounts" && [ ! -w "${T}/flash" ]; }
run() {
  BOOT_TRACE_FLASH="${T}/flash" BOOT_TRACE_STEP="${T}/step" BOOT_TRACE_ROUNDS=${ROUNDS:-60} \
    BOOT_TRACE_MOUNTS="${T}/mounts" BOOT_TRACE_KMSG="${T}/kmsg" BOOT_TRACE_RUN="${T}/run" \
    BOOT_TRACE_LOCK="${T}/lock" BOOT_TRACE_LOCK_WAIT=${LOCK_WAIT:-100} \
    PATH="${T}/bin:${PATH}" timeout 30 bash "${SCRIPT}" >/dev/null 2>&1
}

### 1. No marker: nothing is written, /flash is left alone.
setup
run
check "no marker: no log" '[ ! -e "${T}/flash/boot-trace.log" ]'
check "no marker: /flash not remounted" '[ ! -s "${T}/calls" ]'

### 2. A boot that gets to the end.
setup
mark
run
check "boot: every round logs what systemd waits for" '[ "$(LOG | grep -c "sway.service start waiting")" = 3 ]'
check "boot: the autostart step is logged" 'LOG | grep -q "autostart step: common:.*006-display"'
check "boot: processes stuck in the kernel are logged with where they wait" \
  '[ "$(LOG | sed "/summary/,\$d" | grep -c "D 77 mmc_wait_for_req resize2fs")" = 3 ] && ! LOG | sed "/summary/,\$d" | grep -q "ep_poll"'
check "boot: each kernel line is logged once" '[ "$(LOG | grep -c "kernel line 1$")" = 1 ] && LOG | grep -q "kernel line 3$"'
check "boot: stops once the system is running" '[ "$(cat "${T}/state")" = 3 ]'
check "boot: a summary with the failed units and warnings" \
  'LOG | grep -q "summary (system: running)" && LOG | grep -q "x.service failed" && LOG | grep -q "journal: warning line"'
check "boot: the marker goes, one boot is traced" '[ ! -e "${T}/flash/archr-trace" ]'
check "boot: every round is synced to the card" '[ "$(grep -c "^sync -f" "${T}/calls")" -ge 4 ]'
check "boot: /flash read-only again at the end" 'tail -1 "${T}/calls" | grep -q "remount,ro" && flash_is_ro'
check "boot: nothing left in /run" '[ -z "$(ls -A "${T}/run")" ]'

### 3. A boot that never finishes: bounded, still summarized.
setup
mark
STUCK=1 ROUNDS=4 run
check "stuck: as many rounds as allowed" '[ "$(LOG | grep -c "^--- \[[0-9.]*\] system: starting")" = 4 ]'
check "stuck: summary says the boot never ended" 'LOG | grep -q "summary (system: starting)" && LOG | tail -1 | grep -q "end of trace"'

### 4. The clone quirk remounts /flash read-only in the middle of the trace.
setup
mark
QUIRK_AT=2 run
check "ro mid-trace: the rounds after it are still logged" '[ "$(LOG | grep -c "sway.service start waiting")" = 3 ]'
check "ro mid-trace: summary written and the marker removed" \
  'LOG | tail -1 | grep -q "end of trace" && [ ! -e "${T}/flash/archr-trace" ]'
check "ro mid-trace: /flash read-only at the end" 'flash_is_ro'

### 5. /flash goes read-only again right under a write: tried once more.
setup
mark
: >"${T}/flake"
ROUNDS=1 STUCK=1 run
check "transient failure: the first write still reaches the card" 'LOG | grep -q "^=== \[[0-9.]*\] systemd" && LOG | grep -q "end of trace"'
check "transient failure: /flash read-only at the end" 'flash_is_ro'

### 6. The kernel ring buffer wraps: records are followed by sequence number.
setup
mark
WRAP=1 STUCK=1 ROUNDS=5 run
check "wrap: every kernel record is logged, each once" \
  'each_once 1 2 3 4 5'
check "wrap: with the kernel timestamp" 'LOG | grep -q "^\[ *3\.000000\] kernel line 3$"'
check "wrap: the key=value dictionary lines are not logged" '! LOG | grep -q "SUBSYSTEM="'

### 7. The log is capped: past BOOT_TRACE_MAX it moves to .1.
setup
mark
chmod u+w "${T}/flash"
for i in $(seq 1 2000); do echo "old boot line ${i}"; done >"${T}/flash/boot-trace.log"
chmod a-w "${T}/flash" "${T}/flash/boot-trace.log"
BOOT_TRACE_MAX=4000 STUCK=1 ROUNDS=20 run
check "cap: the log stays under the cap" '[ "$(size "${T}/flash/boot-trace.log")" -le 4000 ]'
check "cap: the previous one is kept, cut to the cap, newest end first" \
  '[ "$(size "${T}/flash/boot-trace.log.1")" -le 4000 ] && [ "$(size "${T}/flash/boot-trace.log.1")" -gt 0 ]'
check "cap: the newest lines are the ones kept" 'LOG | tail -1 | grep -q "end of trace"'
check "cap: the oldest lines are the ones dropped" '! cat "${T}/flash/boot-trace.log"* | grep -q "old boot line 1$"'

### 8. The flash lock is held (the clone quirk has /flash read-write).
setup
mark
SAME_LOCK=
grep -q '/run/archr-flash.lock' "${QUIRK}" && grep -q 'LOCK=${BOOT_TRACE_LOCK:-/run/archr-flash.lock}' "${SCRIPT}" && SAME_LOCK=1
check "lock: the quirk and the trace take the same lock" '[ -n "${SAME_LOCK}" ]'
check "lock: the quirk holds it around its read-write section" \
  'sed -n "/flock -x 9/,/9>>\/run\/archr-flash.lock/p" "${QUIRK}" | grep -q "remount,rw /flash" && sed -n "/flock -x 9/,/9>>\/run\/archr-flash.lock/p" "${QUIRK}" | grep -q "remount,ro /flash"'
( exec 9>>"${T}/lock"; flock 9; exec sleep 30 ) &
HOLDER=$!
for _ in $(seq 1 50); do flock -n "${T}/lock" true || break; command sleep 0.05; done
STUCK=1 ROUNDS=2 LOCK_WAIT=3 run
check "lock: no write to /flash while it is held" '! grep -q "remount" "${T}/calls" 2>/dev/null && [ ! -e "${T}/flash/boot-trace.log" ]'
check "lock: the marker stays, the next boot is traced" '[ -e "${T}/flash/archr-trace" ]'
kill "${HOLDER}" 2>/dev/null; wait "${HOLDER}" 2>/dev/null; HOLDER=
echo 0 >"${T}/state"
run
check "lock: once released, the trace is written" 'LOG | grep -q "end of trace" && [ ! -e "${T}/flash/archr-trace" ]'

### 9. The initramfs side (scripts/init boot_trace).
setup
chmod u+w "${T}/flash"
FN=$(sed -n '/^BOOT_TRACE_DIR=\/flash$/,/^}$/p' "${INIT}")
check "init: boot_trace found in scripts/init" '[ -n "${FN}" ]'
itrace() { PATH="${T}/bin:${PATH}" bash -c "${FN}"'
BOOT_TRACE_DIR="$1"; shift
for s in "$@"; do boot_trace "$s"; done' sh "${T}/flash" "$@"; }
itrace mount_flash mount_roms
check "init: no marker, no log" '[ ! -e "${T}/flash/boot-trace.log" ]'
chmod u+w "${T}/flash"
: >"${T}/flash/archr-trace"
: >"${T}/calls"
itrace mount_roms prepare_sysroot switch_root
check "init: one header, then each step as it starts" \
  '[ "$(LOG | grep -c "^=== boot")" = 1 ] && LOG | grep -q "init: mount_roms$" && LOG | grep -q "init: prepare_sysroot$"'
check "init: dmesg at switch_root" 'LOG | grep -A1 "init: switch_root" | grep -q -- "--- dmesg"'
check "init: /flash read-only again after each line" \
  '[ "$(grep -c "remount,rw" "${T}/calls")" = 3 ] && [ "$(grep -c "remount,ro" "${T}/calls")" = 3 ] && tail -1 "${T}/calls" | grep -q remount,ro'
check "init: the marker stays for systemd" '[ -e "${T}/flash/archr-trace" ]'
chmod -R u+w "${T}/flash"
head -c 300000 /dev/zero | tr '\0' 'x' >"${T}/flash/boot-trace.log"
itrace mount_roms
check "init: a log past 256 KiB moves to .1 at the start of a boot" \
  '[ "$(size "${T}/flash/boot-trace.log.1")" = 262144 ] && [ "$(size "${T}/flash/boot-trace.log")" -lt 4096 ] && LOG | grep -q "^=== boot"'

### 10. Opt-in only: nothing outside the docs creates the marker.
check "opt-in: no script creates /flash/archr-trace" \
  '! grep -rnE ">[[:space:]]*\"?/flash/archr-trace|touch[[:space:]]+\"?/flash/archr-trace" "${PKGS}" --include="*" 2>/dev/null | grep -v "/tests/"'

exit "${FAILED}"
