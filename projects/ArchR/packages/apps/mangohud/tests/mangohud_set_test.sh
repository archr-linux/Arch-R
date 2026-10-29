#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for mangohud_set: runs it against a temporary system.cfg and
# MangoHud.conf with the real get_setting/set_setting helpers.
#   bash projects/ArchR/packages/apps/mangohud/tests/mangohud_set_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
FUNCTIONS="${PKG}/../../archr/profile.d/001-functions"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

# A profile with the device helpers, pointed at the temp system.cfg.
cat >"${TMP}/profile" <<EOF
. "${FUNCTIONS}"
J_CONF="${TMP}/system.cfg"
J_CONF_LOCK="${TMP}/system.cfg.lock"
set_setting() { rewrite_config config_with "\${1}" "\${2}"; }
log() { :; }
EOF
export MANGOHUD_PROFILE="${TMP}/profile"
export MANGOHUD_CONF_DIR="${TMP}/MangoHud"
export MANGOHUD_DEFAULT_CONF="${TMP}/default.conf"
sed "s/@FONT_SIZE@/30/" "${PKG}/config/MangoHud.conf" >"${MANGOHUD_DEFAULT_CONF}"
CONF="${MANGOHUD_CONF_DIR}/MangoHud.conf"

run() { bash "${PKG}/sources/mangohud_set" "$@"; }
check() {
  if eval "${2}"; then
    echo "ok   ${1}"
  else
    echo "FAIL ${1}"
    FAILED=1
  fi
}
# The value of an uncommented option, as MangoHud reads it (last one wins).
option() { awk -F= -v k="$1" '$1 == k { v = $2 } END { print v }' "${CONF}"; }
active() { grep -c "^${1}\(=\|$\)" "${CONF}"; }
config() { printf '%s\n' "$@" >"${TMP}/system.cfg"; }

# Defaults: nothing set yet.
config "system.loglevel=none"
run apply
check "creates the user conf from the shipped one" '[ -f "${CONF}" ]'
check "state defaults to off" 'grep -qx "archr.mangohud.state=off" "${TMP}/system.cfg"'
check "hidden at start when off" '[ "$(option no_display)" = 1 ]'
check "compact layout by default" '[ "$(option hud_compact)" = 1 ] && [ "$(option horizontal)" = 0 ]'
check "default size, alpha, limit, position" \
  '[ "$(option font_size)" = 24 ] && [ "$(option background_alpha)" = 0.50 ] && [ "$(option fps_limit)" = 0 ] && [ "$(option position)" = top-left ]'
check "compact items" \
  '[ "$(option fps)" = 1 ] && [ "$(option cpu_temp)" = 1 ] && [ "$(option gpu_temp)" = 1 ] && [ "$(option ram)" = 0 ] && [ "$(option frame_timing)" = 0 ]'
check "shipped managed options are commented out" '[ "$(active gpu_temp)" = 1 ] && [ "$(active font_size)" = 1 ] && grep -qx "# gpu_temp" "${CONF}"'
check "unmanaged shipped options stay" 'grep -qx "text_outline" "${CONF}" && grep -qx "throttling_status" "${CONF}"'
check "conf file mode" '[ "$(stat -c %a "${CONF}")" = 644 ]'

# A hand edit outside the block survives every apply.
echo "toggle_hud=Shift_L+F5" >>"${CONF}"
echo "font_size = 40 # mine" >>"${CONF}"
config "archr.mangohud.state=on" "archr.mangohud.layout=detailed" "archr.mangohud.position=bottom-right" \
  "archr.mangohud.font_size=30" "archr.mangohud.alpha=75" "archr.mangohud.fps_limit=30"
run apply
run apply
check "user option kept" 'grep -qx "toggle_hud=Shift_L+F5" "${CONF}"'
check "managed option typed by hand is commented out" 'grep -qx "# font_size = 40 # mine" "${CONF}" && [ "$(active font_size)" = 1 ]'
check "one block after repeated applies" '[ "$(grep -c "^### BEGIN ArchR" "${CONF}")" = 1 ] && [ "$(grep -c "^### END ArchR" "${CONF}")" = 1 ]'
check "no comment piles up" '! grep -q "^# # " "${CONF}"'
check "detailed layout" '[ "$(option hud_compact)" = 0 ] && [ "$(option cpu_mhz)" = 1 ] && [ "$(option gpu_core_clock)" = 1 ] && [ "$(option frame_timing)" = 1 ] && [ "$(option time)" = 0 ]'
check "shown when on" '[ "$(option no_display)" = 0 ]'
check "chosen size, alpha, limit, position" \
  '[ "$(option font_size)" = 30 ] && [ "$(option background_alpha)" = 0.75 ] && [ "$(option fps_limit)" = 30 ] && [ "$(option position)" = bottom-right ]'

config "archr.mangohud.layout=fps"
run apply
check "fps only" '[ "$(option fps_only)" = 1 ] && [ "$(option table_columns)" = 1 ] && [ "$(option cpu_stats)" = 0 ] && [ "$(option gpu_stats)" = 0 ]'
config "archr.mangohud.layout=horizontal"
run apply
check "horizontal" '[ "$(option horizontal)" = 1 ] && [ "$(option table_columns)" = 20 ] && [ "$(option hud_no_margin)" = 1 ] && [ "$(option ram)" = 1 ]'

config "archr.mangohud.layout=custom" "archr.mangohud.items=game,gpu_freq,bogus,time,game"
run apply
check "custom items" '[ "$(option exec_name)" = 1 ] && [ "$(option time)" = 1 ] && [ "$(option gpu_stats)" = 1 ] && [ "$(option gpu_core_clock)" = 1 ] && [ "$(option gpu_temp)" = 0 ] && [ "$(option fps)" = 0 ]'
config "archr.mangohud.layout=custom" "archr.mangohud.items=bogus"
run apply
check "custom without known items falls back to compact" '[ "$(option fps)" = 1 ] && [ "$(option cpu_temp)" = 1 ]'

config "archr.mangohud.layout=wide" "archr.mangohud.position=middle" "archr.mangohud.font_size=99" \
  "archr.mangohud.alpha=-5" "archr.mangohud.fps_limit=abc" "archr.mangohud.state=maybe"
run apply
check "invalid values fall back to defaults" \
  '[ "$(option hud_compact)" = 1 ] && [ "$(option position)" = top-left ] && [ "$(option font_size)" = 24 ] && [ "$(option background_alpha)" = 0.50 ] && [ "$(option fps_limit)" = 0 ] && [ "$(option no_display)" = 1 ]'
config "archr.mangohud.alpha=100" "archr.mangohud.font_size=012"
run apply
check "full alpha and leading zeros" '[ "$(option background_alpha)" = 1.00 ] && [ "$(option font_size)" = 12 ]'

# The older subcommands keep their meaning.
config "archr.mangohud.state=off"
run toggle
check "toggle shows" 'grep -qx "archr.mangohud.state=on" "${TMP}/system.cfg" && [ "$(option no_display)" = 0 ]'
run toggle
check "toggle hides" 'grep -qx "archr.mangohud.state=off" "${TMP}/system.cfg" && [ "$(option no_display)" = 1 ]'
run on
check "on" '[ "$(option no_display)" = 0 ]'
run off
check "off" '[ "$(option no_display)" = 1 ]'
run enable
check "enable" 'grep -qx "archr.mangohud.enabled=1" "${TMP}/system.cfg"'
run disable
check "disable" 'grep -qx "archr.mangohud.enabled=0" "${TMP}/system.cfg"'
run on
run nonsense
check "an unknown argument hides the overlay" '[ "$(option no_display)" = 1 ]'
check "no temp files left" '[ -z "$(find "${MANGOHUD_CONF_DIR}" -name "MangoHud.conf.*")" ]'

# A failed write leaves the old conf in place.
cp "${CONF}" "${TMP}/before"
chmod 555 "${MANGOHUD_CONF_DIR}"
if [ "$(id -u)" != 0 ]; then
  run apply 2>/dev/null
  RC=$?
  check "apply fails without touching the conf" '[ ${RC} -ne 0 ] && cmp -s "${CONF}" "${TMP}/before"'
fi
chmod 755 "${MANGOHUD_CONF_DIR}"

exit ${FAILED}
