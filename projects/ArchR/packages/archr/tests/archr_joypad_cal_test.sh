#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-joypad-cal with a fake sysfs: the "calibration" file
# keeps the last line written, which is what the driver would receive.
#   bash projects/ArchR/packages/archr/tests/archr_joypad_cal_test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CAL="$(dirname "${HERE}")/sources/scripts/archr-joypad-cal"
T=$(mktemp -d)
trap 'rm -rf "${T}"' EXIT
FAILED=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi; }

mkdir -p "${T}/drivers/odroidgo3_joypad" "${T}/drivers/archr-singleadc-joypad" "${T}/devices"
make_dev() {  # name driver
  rm -rf "${T}/devices/"* "${T}/real"
  mkdir -p "${T}/real/$1"
  ln -sfn "${T}/drivers/$2" "${T}/real/$1/driver"
  ln -sfn "${T}/real/$1" "${T}/devices/$1"
  printf '%s\n' "x raw=1810 center=1806 fixed=0 neg=200 pos=200 deadzone=64 max=1800 invert=1" \
    "y raw=1820 center=1820 fixed=1 neg=170 pos=190 deadzone=64 max=1800 invert=1" >"${T}/real/$1/calibration"
}
printf 'gameconsole,r36s\0rockchip,rk3326\0' >"${T}/compat"
export ARCHR_JOYPAD_CAL_SYSFS="${T}/devices" ARCHR_JOYPAD_CAL_CONF="${T}/conf" ARCHR_JOYPAD_CAL_COMPAT="${T}/compat"

make_dev odroidgo3-joypad odroidgo3_joypad
A="${T}/real/odroidgo3-joypad/calibration"
check "path found" '[ "$(bash "${CAL}" path)" = "${T}/devices/odroidgo3-joypad/calibration" ]'
# Per-axis deadzone driver: 100 * 1800 / (travel * 97%).
bash "${CAL}" fit x 1810 900 2700
check "fit, per-axis driver" '[ "$(cat "${A}")" = "x center=1810 neg=204 pos=209" ]'
make_dev odroidgo3-joypad odroidgo3_joypad
bash "${CAL}" fit x 1810 900 2700 6
check "fit with a deadzone" '[ "$(cat "${A}")" = "x center=1810 neg=204 pos=209 deadzone=53" ]'
check "fit refuses MIN >= CENTER" '! bash "${CAL}" fit x 1810 1900 2700 2>/dev/null'
check "fit refuses a 50% deadzone" '! bash "${CAL}" fit x 1810 900 2700 50 2>/dev/null'

make_dev joypad archr-singleadc-joypad
A="${T}/real/joypad/calibration"
# Radial driver rescales after the deadzone: 100 * (1800 - dz) / (travel * 97% - dz).
bash "${CAL}" fit x 1810 900 2700 6
check "fit, radial driver" '[ "$(cat "${A}")" = "x center=1810 neg=211 pos=216 deadzone=53" ]'

make_dev joypad archr-singleadc-joypad
bash "${CAL}" save
check "save keeps the board" 'grep -qx "board=gameconsole,r36s" "${T}/conf"'
check "save: auto center not pinned" 'grep -qx "x neg=200 pos=200 deadzone=64" "${T}/conf"'
check "save: measured center kept" 'grep -qx "y center=1820 neg=170 pos=190 deadzone=64" "${T}/conf"'
bash "${CAL}" apply
check "apply writes the saved lines" '[ "$(cat "${A}")" = "y center=1820 neg=170 pos=190 deadzone=64" ]'

make_dev joypad archr-singleadc-joypad
printf 'gameconsole,soysauce\0' >"${T}/compat"
bash "${CAL}" apply 2>/dev/null
check "another board: nothing applied" 'grep -q "^x raw=" "${A}"'

bash "${CAL}" reset
check "reset writes reset and drops the file" '[ "$(cat "${A}")" = reset ] && [ ! -e "${T}/conf" ]'

rm -rf "${T}/devices/"*
check "no support: apply is quiet" 'bash "${CAL}" apply'
check "no support: path exits 2" 'bash "${CAL}" path 2>/dev/null; [ $? = 2 ]'
exit ${FAILED}
