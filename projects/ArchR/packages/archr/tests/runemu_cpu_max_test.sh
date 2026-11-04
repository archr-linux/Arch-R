#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for runemu.sh --cpu-max=: the launcher passes the CPU ceiling a
# module chose for one launch. Only one of the CPU's own frequencies may
# ever reach scaling_max_freq.
#   bash projects/ArchR/packages/archr/tests/runemu_cpu_max_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
RUNEMU="${PKG}/sources/scripts/runemu.sh"
FAILED=0

check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
eval "$(sed -n '/^pick_cpu_max() {/,/^}/p' "${PKG}/profile.d/099-freqfunctions")"
CPUFREQ=$(mktemp -d)
trap 'rm -rf "${CPUFREQ}"' EXIT
mkdir -p "${CPUFREQ}/policy0"
echo "408000 816000 1008000 1416000 " >"${CPUFREQ}/policy0/scaling_available_frequencies"
echo "1512000 " >"${CPUFREQ}/policy0/scaling_boost_frequencies"
export CPUFREQ

for khz in 408000 816000 1416000 1512000; do
  check "${khz} is a ceiling" '[ "$(pick_cpu_max "${khz}")" = "${khz}" ]'
done
for bad in '' 600000 '816000 ' ' 816000' 0816000 816000x '$(reboot)' \
  '816000; reboot' '816000
reboot' 99999999999 -816000 '*'; do
  check "refused: ${bad//$'\n'/\\n}" '[ -z "$(pick_cpu_max "${bad}")" ]'
done
rm "${CPUFREQ}/policy0/scaling_boost_frequencies"
check "no boost list, no boost ceiling" '[ -z "$(pick_cpu_max 1512000)" ]'

# runemu.sh: read from its own word, before the catch-all; the ceiling
# goes through pick_cpu_max and comes after the governor.
parse=$(sed -n '/^for ((i = 1;/,/^done/p' "${RUNEMU}")
check "--cpu-max= is parsed" 'grep -q "^    --cpu-max=\*) CPU_MAX_OVERRIDE=\"\${ARG#\*=}\" ;;" <<<"${parse}"'
check "before the catch-all" '[ "$(grep -n -- "--cpu-max=\*)" <<<"${parse}" | cut -d: -f1)" -lt "$(grep -n -- "--\*|" <<<"${parse}" | cut -d: -f1)" ]'
check "the ceiling goes through pick_cpu_max" 'grep -q "^CPU_MAX=\$(pick_cpu_max \"\${CPU_MAX_OVERRIDE}\")" "${RUNEMU}"'
check "after the governor" '[ "$(grep -n "^\${CPU_GOVERNOR}$" "${RUNEMU}" | cut -d: -f1)" -lt "$(grep -n "^CPU_MAX=" "${RUNEMU}" | cut -d: -f1)" ]'
check "the highest is back after the game" '[ "$(grep -n "set_cpu_max_freq \"\${CPU_MAX}\"" "${RUNEMU}" | cut -d: -f1)" -lt "$(grep -n "^performance$" "${RUNEMU}" | tail -1 | cut -d: -f1)" ]'

run_parse() {
  ARGV=("$@")
  CPU_MAX_OVERRIDE=""
  eval "$(sed -n '/^for ((i = 1;/,/^done/p' "${RUNEMU}")"
  echo "${CPU_MAX_OVERRIDE}"
}
check "the launcher's line" '[ "$(run_parse /roms/snes/m.sfc -Psnes --core=x --governor=ondemand --cpu-max=816000)" = 816000 ]'
check "nothing without them" '[ "$(run_parse /roms/snes/m.sfc -Psnes --core=x)" = "" ]'
check "a ROM path that looks like one is not" '[ "$(run_parse "/roms/snes/--cpu-max=408000.sfc" -Psnes)" = "" ]'

bash -n "${RUNEMU}" && echo "ok   runemu.sh parses" || { echo "FAIL runemu.sh syntax"; FAILED=1; }
exit ${FAILED}
