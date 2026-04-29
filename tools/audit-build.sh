#!/bin/bash
# ArchR Build Audit Script
# Checks for debug flags, sanitizers, and misconfigurations in production builds
# Run on the R36S device: bash /flash/audit-build.sh (copy to boot partition)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
PASS=0; WARN=0; FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}[PASS]${NC} $label = $actual"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${NC} $label = $actual (expected: $expected)"
    FAIL=$((FAIL+1))
  fi
}

warn() {
  echo -e "  ${YELLOW}[WARN]${NC} $1"
  WARN=$((WARN+1))
}

echo "========================================"
echo "  ArchR Production Build Audit"
echo "  $(date)"
echo "  $(uname -r) on $(cat /etc/os-release | grep ^NAME= | cut -d= -f2)"
echo "========================================"

echo ""
echo "=== 1. KERNEL DEBUG FLAGS ==="
# Primary: /boot/config-* (always present)
# Fallback: /proc/config.gz (only if CONFIG_IKCONFIG=y, disabled in production)
KCONF_FILE="/boot/config-$(uname -r)"
if [ -f "$KCONF_FILE" ]; then
  KCONF=$(cat "$KCONF_FILE")
  echo "  Source: $KCONF_FILE"
elif [ -f /proc/config.gz ]; then
  KCONF=$(zcat /proc/config.gz)
  echo "  Source: /proc/config.gz (IKCONFIG enabled — consider disabling for production)"
else
  KCONF=""
  warn "No kernel config found (neither /boot/config-* nor /proc/config.gz)"
fi

if [ -n "$KCONF" ]; then
  check "DEBUG_KERNEL" "not set" "$(echo "$KCONF" | grep -c CONFIG_DEBUG_KERNEL=y | sed 's/1/SET/;s/0/not set/')"
  check "LOCKDEP" "not set" "$(echo "$KCONF" | grep -c CONFIG_LOCKDEP=y | sed 's/1/SET/;s/0/not set/')"
  check "KASAN" "not set" "$(echo "$KCONF" | grep -c CONFIG_KASAN=y | sed 's/1/SET/;s/0/not set/')"
  check "KMEMLEAK" "not set" "$(echo "$KCONF" | grep -c CONFIG_KMEMLEAK=y | sed 's/1/SET/;s/0/not set/')"
  check "FTRACE" "not set" "$(echo "$KCONF" | grep -c CONFIG_FTRACE=y | sed 's/1/SET/;s/0/not set/')"
  check "SCHEDSTATS" "not set" "$(echo "$KCONF" | grep -c CONFIG_SCHEDSTATS=y | sed 's/1/SET/;s/0/not set/')"
  check "PROFILING" "not set" "$(echo "$KCONF" | grep -c CONFIG_PROFILING=y | sed 's/1/SET/;s/0/not set/')"

  echo ""
  echo "  Kernel Timer: $(echo "$KCONF" | grep CONFIG_HZ= | head -1)"
  echo "  Preempt: $(echo "$KCONF" | grep CONFIG_PREEMPT= | head -1)"
  echo "  Optimize: $(echo "$KCONF" | grep CONFIG_CC_OPTIMIZE | head -1)"
  echo "  Frame Pointer: $(echo "$KCONF" | grep CONFIG_FRAME_POINTER= | head -1) (forced on ARM64)"
fi

echo ""
echo "=== 2. MESA / GPU ==="
MESA_VER=$(glxinfo -B 2>/dev/null | grep "OpenGL version" || echo "glxinfo not available")
echo "  Mesa: $MESA_VER"
echo "  PAN_MESA_DEBUG=${PAN_MESA_DEBUG:-unset}"
echo "  MESA_NO_ERROR=${MESA_NO_ERROR:-unset}"
echo "  MESA_SHADER_CACHE_DIR=${MESA_SHADER_CACHE_DIR:-unset}"
for BAD in MESA_DEBUG MESA_VERBOSE GALLIUM_DUMP LIBGL_DEBUG; do
  VAL=$(printenv $BAD 2>/dev/null)
  [ -n "$VAL" ] && warn "$BAD=$VAL should NOT be set in production"
done
[ "$PAN_MESA_DEBUG" = "sync" ] && warn "PAN_MESA_DEBUG=sync kills ~30% FPS"
[ "$PAN_MESA_DEBUG" = "trace" ] && warn "PAN_MESA_DEBUG=trace captures every draw call"

echo ""
echo "=== 3. RETROARCH ==="
RA_CFG="/storage/.config/retroarch/retroarch.cfg"
if [ -f "$RA_CFG" ]; then
  echo "  log_verbosity = $(grep ^log_verbosity "$RA_CFG" | cut -d'"' -f2)"
  echo "  perfcnt_enable = $(grep ^perfcnt_enable "$RA_CFG" | cut -d'"' -f2)"
  echo "  video_driver = $(grep ^video_driver "$RA_CFG" | cut -d'"' -f2)"
  echo "  menu_driver = $(grep ^menu_driver "$RA_CFG" | cut -d'"' -f2)"
  echo "  autosave_interval = $(grep ^autosave_interval "$RA_CFG" | cut -d'"' -f2)"
fi

echo ""
echo "=== 4. EMULATOR BINARIES ==="
for bin in /usr/bin/retroarch /usr/bin/ppsspp /usr/bin/flycast /usr/bin/melonDS /usr/bin/mupen64plus; do
  [ -x "$bin" ] || continue
  STRIPPED=$(file "$bin" | grep -o "not stripped\|stripped")
  SIZE=$(du -h "$bin" | cut -f1)
  echo "  $bin: $STRIPPED ($SIZE)"
done

echo ""
echo "=== 5. LIBRETRO CORES ==="
TOTAL=0; UNSTRIPPED=0
for core in /tmp/cores/*.so /usr/lib/libretro/*.so; do
  [ -f "$core" ] || continue
  TOTAL=$((TOTAL+1))
  file "$core" | grep -q "not stripped" && UNSTRIPPED=$((UNSTRIPPED+1))
done
echo "  Total cores: $TOTAL"
echo "  Unstripped: $UNSTRIPPED"
[ "$UNSTRIPPED" -gt 0 ] && warn "$UNSTRIPPED cores not stripped"

echo ""
echo "=== 6. SYSTEM STATE ==="
echo "  CPU governor: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)"
echo "  CPU freq: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null) kHz"
echo "  GPU governor: $(cat /sys/class/devfreq/ff400000.gpu/governor 2>/dev/null)"
echo "  GPU freq: $(cat /sys/class/devfreq/ff400000.gpu/cur_freq 2>/dev/null) Hz"
echo "  DMC governor: $(cat /sys/class/devfreq/dmc/governor 2>/dev/null)"
echo "  Temperature: $(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)m°C"
echo "  MemAvailable: $(grep MemAvailable /proc/meminfo | awk '{print $2}') kB"
echo "  CmaTotal: $(grep CmaTotal /proc/meminfo | awk '{print $2}') kB"
echo "  CmaFree: $(grep CmaFree /proc/meminfo | awk '{print $2}') kB"
echo "  Swap: $(swapon --show --noheadings 2>/dev/null | head -1 || echo 'none')"
echo "  ZRAM: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo 'not configured')"
echo "  vm.swappiness: $(sysctl -n vm.swappiness 2>/dev/null)"
echo "  vm.vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null)"

echo ""
echo "=== 7. ACTIVE SERVICES ==="
systemctl list-units --state=running --type=service --no-pager --no-legend 2>/dev/null | awk '{print "  " $1}'

echo ""
echo "========================================"
echo -e "  Results: ${GREEN}$PASS PASS${NC}  ${YELLOW}$WARN WARN${NC}  ${RED}$FAIL FAIL${NC}"
echo "========================================"
