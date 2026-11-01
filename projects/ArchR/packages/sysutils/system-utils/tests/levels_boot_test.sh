#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Boot and resume order of the levels: archr-levels converts the saved
# levels once and holds them; the scripts that run around it must only ask
# it to re-apply them. A value read from system.cfg by a script that ran
# before the conversion would be written back over it.
#   bash projects/ArchR/packages/sysutils/system-utils/tests/levels_boot_test.sh

set -u
PKGS=$(cd "$(dirname "$0")/../../.." && pwd)
FAILED=0
fail() {
  echo "FAIL: ${*}"
  FAILED=1
}
unit_has() {
  grep -q "^${2}" "${PKGS}/${1}" || fail "${1}: no '${2}'"
}

unit_has sysutils/autostart/system.d/archr-autostart.service "After=.*archr-levels.service"
unit_has sysutils/autostart/system.d/archr-autostart.service "Wants=.*archr-levels.service"
unit_has sysutils/system-utils/system.d/archr-levels.service "Type=notify"
unit_has sysutils/system-utils/system.d/archr-levels.service "After=.*userconfig.service"
unit_has sysutils/system-utils/system.d/archr-levels.service "Before=.*input.service"

SCRIPTS=(
  archr/autostart/006-display
  archr/autostart/050-audio
  sysutils/sleep/sources/sleep.sh
  sysutils/system-utils/sources/scripts/headphone_sense
  sysutils/system-utils/sources/devices/RK3566/headphone_sense
)
for SCRIPT in "${SCRIPTS[@]}"; do
  FILE="${PKGS}/${SCRIPT}"
  # Never a level read from system.cfg, never a second owner of the sink.
  grep -nE 'get_setting "?(audio\.volume|display\.brightness)' "${FILE}" && fail "${SCRIPT} reads a level"
  grep -nE '(volume|brightness)( set)? +"?\$' "${FILE}" && fail "${SCRIPT} sets a level from a variable"
  grep -nE 'amixer .*-M .*(set|sset) .*DEVICE_AUDIO_MIXER' "${FILE}" && fail "${SCRIPT} sets the mixer volume"
done
grep -q "archr-levels brightness restore" "${PKGS}/archr/autostart/006-display" || fail "006-display does not restore"
grep -q "archr-levels volume restore" "${PKGS}/archr/autostart/050-audio" || fail "050-audio does not restore"
grep -q "archr-levels volume restore" "${PKGS}/sysutils/sleep/sources/sleep.sh" || fail "sleep.sh does not restore the volume"
grep -q "archr-levels brightness restore" "${PKGS}/sysutils/sleep/sources/sleep.sh" || fail "sleep.sh does not restore the brightness"

[ ${FAILED} -eq 0 ] && echo "levels_boot_test: OK"
exit ${FAILED}
