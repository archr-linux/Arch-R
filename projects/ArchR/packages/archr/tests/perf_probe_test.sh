#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-perf-probe on a fake /proc and /sys: it finds the
# busiest process after the warm-up, samples its busiest thread each second
# and publishes the summary on SIGTERM.
#   bash projects/ArchR/packages/archr/tests/perf_probe_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE="$(dirname "${HERE}")/sources/scripts/archr-perf-probe"
FAILED=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
ROOT=$(mktemp -d)
trap 'kill "${TICKER}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
stat() { # dir pid name utime stime
  echo "$2 ($3) S 1 1 1 0 -1 0 0 0 0 0 $4 $5 0 0 20 0 1 0 100" >"$1/stat"
}
mkdir -p "${ROOT}/proc/10/task/10" "${ROOT}/proc/10/task/11" "${ROOT}/proc/20/task/20" \
  "${ROOT}/cpufreq/policy0" "${ROOT}/battery"
stat "${ROOT}/proc/10" 10 "retro arch) (x" 0 0
stat "${ROOT}/proc/10/task/10" 10 "retroarch" 0 0
stat "${ROOT}/proc/10/task/11" 11 "audio" 0 0
stat "${ROOT}/proc/20" 20 "daemon" 0 0
echo 816000 >"${ROOT}/cpufreq/policy0/scaling_max_freq"
echo Discharging >"${ROOT}/battery/status"
echo -480000 >"${ROOT}/battery/current_avg"
# The emulator's main thread runs flat out: 100 ticks a second, plus the
# audio thread's 20; the daemon barely moves.
(
  t=0
  while :; do
    t=$((t + 1))
    stat "${ROOT}/proc/10" 10 "retro arch) (x" $((t * 6)) $((t * 6))
    stat "${ROOT}/proc/10/task/10" 10 retroarch $((t * 5)) $((t * 5))
    stat "${ROOT}/proc/10/task/11" 11 audio $((t * 1)) $((t * 1))
    stat "${ROOT}/proc/20" 20 daemon "${t}" 0
    sleep 0.1
  done
) &
TICKER=$!
ARCHR_PROC="${ROOT}/proc" CPUFREQ="${ROOT}/cpufreq" ARCHR_BATTERY="${ROOT}/battery" \
  ARCHR_PERF_OUT="${ROOT}/run/perf-last.json" ARCHR_PERF_WARMUP=1 bash "${PROBE}" &
PROBE_PID=$!
sleep 4.5
kill -TERM "${PROBE_PID}"
wait "${PROBE_PID}"
OUT=$(cat "${ROOT}/run/perf-last.json" 2>/dev/null)
echo "     ${OUT}"
field() { jq -r ".$1" <<<"${OUT}"; }
check "published" '[ -n "${OUT}" ] && ! [ -e "${ROOT}/run/perf-last.json.tmp" ]'
check "the ceiling it ran under" '[ "$(field cpu_max_khz)" = 816000 ]'
check "about three seconds" '[ "$(field seconds)" -ge 2 ] && [ "$(field seconds)" -le 4 ]'
check "the busiest thread is saturated" '[ "$(field busy_p95)" -ge 92 ]'
check "every second at the limit" '[ "$(field limit_seconds)" = "$(field seconds)" ]'
check "the discharge current in mA" '[ "$(field current_ma)" = 480 ]'
check "a start time" '[ "$(field started)" -gt 1700000000 ]'
bash -n "${PROBE}" && echo "ok   the probe parses" || { echo "FAIL probe syntax"; FAILED=1; }
exit ${FAILED}
