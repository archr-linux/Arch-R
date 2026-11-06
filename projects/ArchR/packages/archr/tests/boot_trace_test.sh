#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the boot trace on /flash: boot_trace in the initramfs
# (scripts/init) and archr-boot-trace under systemd. A boot stuck on a
# frozen screen must leave, on the one partition a PC reads, the step it
# reached, what systemd still waits for and what is stuck in the kernel.
# Fake tools on PATH; no root, no devices.
#   bash projects/ArchR/packages/archr/tests/boot_trace_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKGS="$(cd "${HERE}/../.." && pwd)"
SCRIPT="${PKGS}/archr/sources/scripts/archr-boot-trace"
INIT="${PKGS}/sysutils/busybox/scripts/init"
T=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "${T}"' EXIT
FAILED=0
ok() { echo "ok - $1"; }
fail() { echo "FAIL - $1"; FAILED=1; }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

setup() {
  rm -rf "${T:?}"/{flash,bin,calls,state}
  mkdir -p "${T}/flash" "${T}/bin"
  echo 0 >"${T}/state"
  tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${T}" "$2" >"${T}/bin/$1"; chmod +x "${T}/bin/$1"; }
  tool mount 'echo "mount $*" >>"$T/calls"'
  tool sync 'echo "sync $*" >>"$T/calls"'
  tool sleep ':'
  tool journalctl 'echo "journal: warning line"'
  # Each call of is-system-running moves the boot on; dmesg grows with it.
  tool systemctl '
case "$1" in
  is-system-running)
    n=$(($(cat "$T/state") + 1)); echo $n >"$T/state"
    if [ -n "${STUCK:-}" ] || [ $n -lt 3 ]; then echo starting; else echo running; fi ;;
  list-jobs) echo "42 sway.service start waiting" ;;
  is-active) echo active; echo activating ;;
  --failed) echo "x.service failed" ;;
esac'
  tool dmesg 'for i in $(seq 1 "$(cat "$T/state")"); do echo "[ $i.0] kernel line $i"; done'
  tool ps 'echo "S 1 ep_poll /sbin/init"; echo "D 77 mmc_wait_for_req resize2fs"'
  echo "common:/usr/lib/autostart/common/006-display" >"${T}/step"
}
LOG() { cat "${T}/flash/boot-trace.log" 2>/dev/null; }
run() {
  BOOT_TRACE_FLASH="${T}/flash" BOOT_TRACE_STEP="${T}/step" BOOT_TRACE_ROUNDS=${ROUNDS:-60} \
    PATH="${T}/bin:${PATH}" timeout 30 bash "${SCRIPT}" >/dev/null 2>&1
}

### 1. No marker: nothing is written, /flash is left alone.
setup
run
check "no marker: no log" '[ ! -e "${T}/flash/boot-trace.log" ]'
check "no marker: /flash not remounted" '[ ! -s "${T}/calls" ]'

### 2. A boot that gets to the end.
setup
: >"${T}/flash/archr-trace"
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
check "boot: /flash read-only again at the end" 'tail -1 "${T}/calls" | grep -q "remount,ro"'

### 3. A boot that never finishes: bounded, still summarized.
setup
: >"${T}/flash/archr-trace"
STUCK=1 ROUNDS=4 run
check "stuck: as many rounds as allowed" '[ "$(LOG | grep -c "^--- \[[0-9.]*\] system: starting")" = 4 ]'
check "stuck: summary says the boot never ended" 'LOG | grep -q "summary (system: starting)" && LOG | tail -1 | grep -q "end of trace"'

### 4. The initramfs side (scripts/init boot_trace).
setup
FN=$(sed -n '/^BOOT_TRACE_DIR=\/flash$/,/^}$/p' "${INIT}")
check "init: boot_trace found in scripts/init" '[ -n "${FN}" ]'
itrace() { PATH="${T}/bin:${PATH}" bash -c "${FN}"'
BOOT_TRACE_DIR="$1"; shift
for s in "$@"; do boot_trace "$s"; done' sh "${T}/flash" "$@"; }
itrace mount_flash mount_roms
check "init: no marker, no log" '[ ! -e "${T}/flash/boot-trace.log" ]'
: >"${T}/flash/archr-trace"
itrace mount_roms prepare_sysroot switch_root
check "init: one header, then each step as it starts" \
  '[ "$(LOG | grep -c "^=== boot")" = 1 ] && LOG | grep -q "init: mount_roms$" && LOG | grep -q "init: prepare_sysroot$"'
check "init: dmesg at switch_root" 'LOG | grep -A1 "init: switch_root" | grep -q -- "--- dmesg"'
check "init: /flash read-only again after each line" \
  '[ "$(grep -c "remount,rw" "${T}/calls")" = 3 ] && [ "$(grep -c "remount,ro" "${T}/calls")" = 3 ] && tail -1 "${T}/calls" | grep -q remount,ro'
check "init: the marker stays for systemd" '[ -e "${T}/flash/archr-trace" ]'

exit "${FAILED}"
