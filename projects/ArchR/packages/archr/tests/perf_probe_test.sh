#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-perf-probe on a fake /proc and /sys: it measures only
# the busiest process under the launch (never a busier one elsewhere),
# samples its busiest thread each second, counts idle and saturated seconds,
# publishes the summary on SIGTERM and leaves no process behind.
#   bash projects/ArchR/packages/archr/tests/perf_probe_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PROBE="$(dirname "${HERE}")/sources/scripts/archr-perf-probe"
FAILED=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
ROOT=$(mktemp -d)
TICKER=""
trap 'kill ${TICKER} 2>/dev/null; rm -rf "${ROOT}"' EXIT
stat() { # dir pid name parent utime stime
  echo "$2 ($3) S $4 1 1 0 -1 0 0 0 0 0 $5 $6 0 0 20 0 1 0 100" >"$1/stat"
}

# runemu.sh is 5; under it the emulator 10 (main thread 10, audio 11) and a
# helper 12; 20, outside the launch, runs flat out the whole time.
# $1: the emulator main thread's ticks per 0.1 s (10 = 100 %).
run() {
  local busy=$1
  rm -rf "${ROOT}/proc" "${ROOT}/run"
  mkdir -p "${ROOT}/proc/5" "${ROOT}/proc/10/task/10" "${ROOT}/proc/10/task/11" \
    "${ROOT}/proc/12" "${ROOT}/proc/20/task/20" "${ROOT}/cpufreq/policy0" "${ROOT}/battery"
  echo 816000 >"${ROOT}/cpufreq/policy0/scaling_max_freq"
  echo Discharging >"${ROOT}/battery/status"
  echo -480000 >"${ROOT}/battery/current_avg"
  (
    t=0
    while :; do
      t=$((t + 1))
      stat "${ROOT}/proc/5" 5 "runemu.sh" 1 0 0
      stat "${ROOT}/proc/10" 10 "retro arch) (x" 5 $((t * busy)) $((t * 1))
      stat "${ROOT}/proc/10/task/10" 10 retroarch 5 $((t * busy)) 0
      stat "${ROOT}/proc/10/task/11" 11 audio 5 $((t * 1)) 0
      stat "${ROOT}/proc/12" 12 helper 5 0 0
      stat "${ROOT}/proc/20" 20 "busy daemon" 1 $((t * 10)) 0
      stat "${ROOT}/proc/20/task/20" 20 "busy daemon" 1 $((t * 10)) 0
      sleep 0.1
    done
  ) &
  TICKER=$!
  sleep 0.3
  ARCHR_PROC="${ROOT}/proc" CPUFREQ="${ROOT}/cpufreq" ARCHR_BATTERY="${ROOT}/battery" \
    ARCHR_PERF_OUT="${ROOT}/run/perf-last.json" ARCHR_PERF_WARMUP=1 bash "${PROBE}" 5 &
  local probe=$!
  sleep 4.5
  CHILDREN=$(pgrep -P "${probe}" | tr '\n' ' ')
  kill -TERM "${probe}"
  wait "${probe}"
  kill "${TICKER}" 2>/dev/null
  wait "${TICKER}" 2>/dev/null
  OUT=$(cat "${ROOT}/run/perf-last.json" 2>/dev/null)
  echo "     ${OUT}"
}
field() { jq -r ".$1" <<<"${OUT}"; }
gone() {
  local pid
  for pid in ${CHILDREN}; do kill -0 "${pid}" 2>/dev/null && return 1; done
  return 0
}

# The emulator at half its thread: the daemon at 100 % must not count.
run 5
check "published" '[ -n "${OUT}" ] && ! [ -e "${ROOT}/run/perf-last.json.tmp" ]'
check "the ceiling it ran under" '[ "$(field cpu_max_khz)" = 816000 ]'
check "about three seconds" '[ "$(field seconds)" -ge 2 ] && [ "$(field seconds)" -le 4 ]'
check "the launch's emulator, not the busy daemon" '[ "$(field busy_p95)" -ge 40 ] && [ "$(field busy_p95)" -le 60 ]'
check "no second at the limit" '[ "$(field limit_seconds)" = 0 ]'
check "no idle second" '[ "$(field idle_seconds)" = 0 ]'
check "the discharge current in mA" '[ "$(field current_ma)" = 480 ]'
check "a start time" '[ "$(field started)" -gt 1700000000 ]'
check "its sleep is gone" 'sleep 0.2; [ -n "${CHILDREN}" ] && gone'

run 10
check "saturated: every second at the limit" '[ "$(field busy_p95)" -ge 92 ] && [ "$(field limit_seconds)" = "$(field seconds)" ]'
check "its sleep is gone" 'sleep 0.2; gone'

run 1
check "waiting: every second idle" '[ "$(field idle_seconds)" = "$(field seconds)" ]'

bash -n "${PROBE}" && echo "ok   the probe parses" || { echo "FAIL probe syntax"; FAILED=1; }
exit ${FAILED}
