#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for runemu.sh --governor=: the launcher passes the CPU governor a
# module chose for one launch. runemu.sh runs the governor as a function
# name, so only the four governor functions may come out of the override;
# anything else leaves the user's setting.
#   bash projects/ArchR/packages/archr/tests/runemu_governor_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
RUNEMU="${PKG}/sources/scripts/runemu.sh"
FAILED=0

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
# The function as the profile defines it, without the rest of the profile.
eval "$(sed -n '/^pick_governor() {/,/^}/p' "${PKG}/profile.d/099-freqfunctions")"
pick() { pick_governor "$1" "$2"; }

for governor in performance ondemand schedutil powersave; do
  check "${governor} overrides the setting" '[ "$(pick "${governor}" ondemand)" = "${governor}" ]'
done
for bad in '' 'userspace' 'performance; reboot' '$(reboot)' 'performance reboot' \
  'Performance' '../performance' 'performance
reboot'; do
  check "refused: ${bad//$'\n'/\\n}" '[ "$(pick "${bad}" schedutil)" = schedutil ]'
done

# runemu.sh: the argument is read from its own word, before the catch-all
# that skips unknown --options, and the setting goes through pick_governor.
parse=$(sed -n '/^for ((i = 1;/,/^done/p' "${RUNEMU}")
check "--governor= is parsed" 'grep -q "^    --governor=\*) GOVERNOR_OVERRIDE=\"\${ARG#\*=}\" ;;" <<<"${parse}"'
check "before the catch-all" '[ "$(grep -n -- "--governor=\*)" <<<"${parse}" | cut -d: -f1)" -lt "$(grep -n -- "--\*|" <<<"${parse}" | cut -d: -f1)" ]'
check "the override starts empty" 'grep -qx "GOVERNOR_OVERRIDE=\"\"" "${RUNEMU}"'
check "the setting goes through pick_governor" \
  'grep -A1 "^CPU_GOVERNOR=\$(get_setting \"cpugovernor\"" "${RUNEMU}" | grep -q pick_governor || grep -q "^CPU_GOVERNOR=\$(pick_governor \"\${GOVERNOR_OVERRIDE}\" \"\${CPU_GOVERNOR}\")" "${RUNEMU}"'

# The parse loop itself, run on a launcher command line.
run_parse() {
  ARGV=("$@")
  GOVERNOR_OVERRIDE=""
  eval "$(sed -n '/^for ((i = 1;/,/^done/p' "${RUNEMU}")"
  echo "${GOVERNOR_OVERRIDE}"
}
check "the launcher's line" '[ "$(run_parse /roms/n64/m.z64 -Pn64 --core=x --emulator=y --controllers=z --governor=performance)" = performance ]'
check "no override without it" '[ -z "$(run_parse /roms/n64/m.z64 -Pn64 --core=x)" ]'
check "a ROM path that looks like one is not" '[ -z "$(run_parse "/roms/n64/--governor=powersave.z64" -Pn64)" ]'

bash -n "${RUNEMU}" && echo "ok   runemu.sh parses" || { echo "FAIL runemu.sh syntax"; FAILED=1; }
exit ${FAILED}
