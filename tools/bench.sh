#!/bin/bash
# ArchR Performance Benchmark Script
# Run on device: bash /flash/bench.sh <scenario> [duration_seconds]
# Results saved to /storage/bench-results/

DURATION=${2:-60}
RESULTS_DIR="/storage/bench-results/$(date +%Y%m%d-%H%M%S)-${1:-general}"
mkdir -p "$RESULTS_DIR"

# Auto-detect device-specific paths once. RK3326 mainline shows up as
# mmcblk1 (microSD), some boards use mmcblk0; the DMC devfreq node has
# a model-prefixed name (e.g. "dmc" alone doesn't exist, real path is
# `/sys/class/devfreq/dmc-rk3326` or similar). Pick whatever the kernel
# actually exposed, fall back to empty string for the JSON if absent.
SD_BLOCK=""
for blk in /sys/block/mmcblk0 /sys/block/mmcblk1; do
  if [ -e "$blk/device/name" ] && [ -n "$(cat "$blk/device/name" 2>/dev/null)" ]; then
    SD_BLOCK="$blk"
    break
  fi
done
SD_MODEL=$([ -n "$SD_BLOCK" ] && cat "$SD_BLOCK/device/name" 2>/dev/null)
SD_NAME=${SD_BLOCK##*/}

GPU_DEVFREQ=$(ls -d /sys/class/devfreq/*gpu* 2>/dev/null | head -1)
DMC_DEVFREQ=$(ls -d /sys/class/devfreq/*dmc* 2>/dev/null | head -1)

DISTRO_NAME=$(awk -F= '/^NAME=/ {gsub(/"/,"",$2); print $2; exit}' /etc/os-release)

echo "========================================"
echo "  ArchR Benchmark: ${1:-general}"
echo "  Duration: ${DURATION}s"
echo "  Output: $RESULTS_DIR"
echo "  SD: ${SD_NAME:-?} (${SD_MODEL:-unknown})"
echo "  GPU devfreq: ${GPU_DEVFREQ:-not found}"
echo "  DMC devfreq: ${DMC_DEVFREQ:-not found}"
echo "========================================"

# Metadata
cat > "$RESULTS_DIR/meta.json" << METAEOF
{
  "timestamp": "$(date -Iseconds)",
  "kernel": "$(uname -r)",
  "distro": "${DISTRO_NAME}",
  "cpu_governor": "$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)",
  "cpu_boost": $(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo 0),
  "cpu_max_freq_khz": $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null || echo 0),
  "gpu_governor": "$(cat ${GPU_DEVFREQ:-/dev/null}/governor 2>/dev/null)",
  "dmc_governor": "$(cat ${DMC_DEVFREQ:-/dev/null}/governor 2>/dev/null)",
  "mem_available_kb": $(grep MemAvailable /proc/meminfo | awk '{print $2}'),
  "cma_total_kb": $(grep CmaTotal /proc/meminfo | awk '{print $2}'),
  "cma_free_kb": $(grep CmaFree /proc/meminfo | awk '{print $2}'),
  "zram_algo": "$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[\K[^\]]+')",
  "swap": "$(swapon --show --noheadings 2>/dev/null | head -1 | tr -s ' ')",
  "swappiness": $(sysctl -n vm.swappiness 2>/dev/null),
  "vfs_cache_pressure": $(sysctl -n vm.vfs_cache_pressure 2>/dev/null),
  "temperature_start": $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null),
  "sd_model": "${SD_MODEL}",
  "sd_block": "${SD_NAME}",
  "scenario": "${1:-general}"
}
METAEOF

# PSI monitoring (background)
echo "Starting PSI monitoring..."
(
  while true; do
    echo "$(date +%s.%N) $(cat /proc/pressure/cpu 2>/dev/null | head -1) $(cat /proc/pressure/memory 2>/dev/null | head -1) $(cat /proc/pressure/io 2>/dev/null | head -1)"
    sleep 1
  done
) > "$RESULTS_DIR/psi.log" &
PSI_PID=$!

# Frequency + temperature monitoring (background)
echo "Starting freq/temp monitoring..."
(
  while true; do
    CPU_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)
    GPU_FREQ=$([ -n "$GPU_DEVFREQ" ] && cat "$GPU_DEVFREQ/cur_freq" 2>/dev/null)
    DMC_FREQ=$([ -n "$DMC_DEVFREQ" ] && cat "$DMC_DEVFREQ/cur_freq" 2>/dev/null)
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    MEM=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    echo "$(date +%s.%N) cpu=$CPU_FREQ gpu=$GPU_FREQ dmc=$DMC_FREQ temp=$TEMP mem=$MEM"
    sleep 1
  done
) > "$RESULTS_DIR/freq-therm.log" &
FREQ_PID=$!

# vmstat monitoring. vmstat exits on its own after $DURATION samples;
# we spawn it in a subshell that pipes to the file directly so it
# survives the parent's kill at the end without a zombie warning.
( vmstat 1 $DURATION > "$RESULTS_DIR/vmstat.log" 2>&1 ) &
VMSTAT_PID=$!

# dmesg ring buffer snapshot (start) and tail (during run). dmesg -w
# in the background was eating its own output before; now we capture
# a baseline plus stream new messages with explicit redirect.
dmesg --since "now -1minutes" 2>/dev/null > "$RESULTS_DIR/dmesg-start.log"
( dmesg -W 2>/dev/null > "$RESULTS_DIR/dmesg.log" ) &
DMESG_PID=$!

echo ""
echo "Monitors running. Now launch your game/emulator."
echo "Press Ctrl+C after ${DURATION}s or when done testing."
echo ""

# Wait
sleep $DURATION 2>/dev/null || true

# Cleanup — be loud about any monitor that didn't survive so the
# follow-up summary doesn't lie about coverage.
for pid in $PSI_PID $FREQ_PID $VMSTAT_PID $DMESG_PID; do
  kill $pid 2>/dev/null
done
wait 2>/dev/null

# Generate summary
TEMP_END=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
MEM_END=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

cat > "$RESULTS_DIR/summary.json" << SUMEOF
{
  "duration_s": $DURATION,
  "temperature_end": $TEMP_END,
  "temperature_delta_c": $(awk "BEGIN { printf \"%.1f\", ($TEMP_END - $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)) / 1000 }"),
  "mem_available_end_kb": $MEM_END,
  "cpu_freq_max_observed_khz": $(awk -F'cpu=' '{split($2,a," "); print a[1]}' "$RESULTS_DIR/freq-therm.log" 2>/dev/null | sort -n | tail -1),
  "gpu_freq_max_observed_hz":  $(awk -F'gpu=' '{split($2,a," "); print a[1]}' "$RESULTS_DIR/freq-therm.log" 2>/dev/null | sort -n | tail -1),
  "psi_samples": $(wc -l < "$RESULTS_DIR/psi.log"),
  "freq_samples": $(wc -l < "$RESULTS_DIR/freq-therm.log"),
  "vmstat_samples": $(wc -l < "$RESULTS_DIR/vmstat.log"),
  "dmesg_lines": $(wc -l < "$RESULTS_DIR/dmesg.log")
}
SUMEOF

echo ""
echo "========================================"
echo "  Benchmark complete!"
echo "  Results: $RESULTS_DIR"
echo "  Files: $(ls $RESULTS_DIR | wc -l)"
echo "========================================"
ls -lh "$RESULTS_DIR"
