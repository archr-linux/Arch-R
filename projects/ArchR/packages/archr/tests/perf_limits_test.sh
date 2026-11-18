#!/bin/bash
# Host test for the user's clock ceilings in 099-freqfunctions
# (user_cpu_cap, user_gpu_cap, the boost rule of set_cpu_max_freq highest)
# with fake cpufreq/devfreq folders and a stubbed get_setting.
#   bash projects/ArchR/packages/archr/tests/perf_limits_test.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

C=${TMP}/cpufreq
mkdir -p "${C}/policy0" "${TMP}/gpu"
echo "408000 816000 1008000 1416000" >"${C}/policy0/scaling_available_frequencies"
echo "1512000" >"${C}/policy0/scaling_boost_frequencies"
echo 1416000 >"${C}/policy0/scaling_max_freq"
echo 0 >"${C}/boost"
echo "200000000 300000000 400000000 560000000 600000000 650000000" >"${TMP}/gpu/available_frequencies"
echo 200000000 >"${TMP}/gpu/min_freq"

# The functions with the real sysfs root moved into the scratch folder.
sed -e "s#/sys/devices/system/cpu/cpufreq#${C}#g" -e 's#^\. /etc/os-release##' \
    -e 's#^\[\[ -f \${GOVERNORS} \]\] && source \${GOVERNORS}##' \
    "${HERE}/profile.d/099-freqfunctions" >"${TMP}/freq"
SETTINGS=${TMP}/settings
: >"${SETTINGS}"
get_setting() { sed -n "s/^$1=//p" "${SETTINGS}"; }
CPUFREQ=${C}
GPU_FREQ=${TMP}/gpu
# shellcheck source=/dev/null
. "${TMP}/freq"
GPU_FREQ=${TMP}/gpu
max() { cat "${C}/policy0/scaling_max_freq"; }

expect "no cap" "" "$(user_cpu_cap)"
echo "system.cpu.max_khz=999" >"${SETTINGS}"
expect "a cap that is not a frequency is ignored" "" "$(user_cpu_cap)"
echo "system.cpu.max_khz=1008000" >"${SETTINGS}"
expect "a cap that is one" "1008000" "$(user_cpu_cap)"
set_cpu_max_freq highest
expect "highest stops at the cap" "1008000" "$(max)"
set_cpu_max_freq 1416000
expect "a launch ceiling stops at the cap" "1008000" "$(max)"
set_cpu_max_freq 816000
expect "a lower launch ceiling stays" "816000" "$(max)"

: >"${SETTINGS}"
set_cpu_max_freq highest
expect "highest without boost leaves the turbo OPP out" "1416000" "$(max)"
echo 1 >"${C}/boost"
set_cpu_max_freq highest
expect "highest with boost reaches it" "1512000" "$(max)"
echo "system.cpu.max_khz=1512000" >"${SETTINGS}"
expect "the turbo OPP is a valid cap" "1512000" "$(user_cpu_cap)"

echo "system.gpu.max_hz=400000000" >"${SETTINGS}"
expect "gpu cap" "400000000" "$(user_gpu_cap)"
set_gpu_min_freq highest
expect "gpu min stops at the cap" "400000000" "$(cat "${TMP}/gpu/min_freq")"
echo "system.gpu.max_hz=123" >"${SETTINGS}"
expect "a gpu cap that is not a frequency is ignored" "" "$(user_gpu_cap)"

bash -n "${HERE}/sources/scripts/archr-perf-limits" || fail "archr-perf-limits parses"
[ ${FAILED} -eq 0 ] && echo "ok   perf limits"
exit ${FAILED}
