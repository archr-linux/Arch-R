#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Host test for start_yabasanshiro.sh: per-game config names (plain game and
# .m3u playlist, old "Game.chd.config" migrated, never overwritten), the BIOS
# argument with spaces and the exit code, with a stub emulator.
#   bash projects/ArchR/packages/emulators/standalone/yabasanshiro-arch/tests/start_yabasanshiro_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }

S="${TMP}/storage"
CONF="${S}/.config/yabasanshiro"
mkdir -p "${TMP}/bin" "${TMP}/src" "${CONF}" "${S}/roms/saturn" "${S}/roms/bios/my bios" "${TMP}/log"
echo '{"template":true}' >"${TMP}/src/.config"
touch "${CONF}/input.cfg"
cat >"${TMP}/bin/yabasanshiro" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '[%s]' "$a"; done >"${TMPOUT}"
exit "${STUB_RC:-0}"
STUB
chmod +x "${TMP}/bin/yabasanshiro"
cat >"${TMP}/profile" <<PROFILE
set_kill() { :; }
get_setting() { [ "\$1" = use_hlebios ] && echo "\${USE_HLE:-0}"; }
PATH="${TMP}/bin:\${PATH}"
PROFILE
sed -e "s#^\. /etc/profile#. ${TMP}/profile#" \
    -e "s#/usr/config/yabasanshiro#${TMP}/src#g" \
    -e "s#/var/log#${TMP}/log#g" \
    -e "s#/storage#${S}#g" \
    "${PKG}/scripts/start_yabasanshiro.sh" >"${TMP}/start.sh"
bash -n "${TMP}/start.sh" || fail "syntax"
export TMPOUT="${TMP}/out"

run() { bash "${TMP}/start.sh" "$@" >/dev/null 2>&1; }

# Plain game: new name created from the template.
run "${S}/roms/saturn/Game A.chd" saturn
expect "template copy" '{"template":true}' "$(cat "${CONF}/Game A.config")"

# Old name migrated, existing new name never overwritten.
echo '{"old":1}' >"${CONF}/Game B.chd.config"
run "${S}/roms/saturn/Game B.chd" saturn
expect "migrated" '{"old":1}' "$(cat "${CONF}/Game B.config")"
echo '{"old":2}' >"${CONF}/Game B.chd.config"
run "${S}/roms/saturn/Game B.chd" saturn
expect "not overwritten" '{"old":1}' "$(cat "${CONF}/Game B.config")"

# Playlist: the config follows the first disc (comments, blank lines, BOM, CR,
# subfolder), not the playlist.
mkdir -p "${S}/roms/saturn/Grandia"
printf '\xef\xbb\xbf# discs\r\n\r\n  Grandia/Grandia (Disc 1).chd  \r\nGrandia/Grandia (Disc 2).chd\r\n' >"${S}/roms/saturn/Grandia.m3u"
echo '{"grandia":1}' >"${CONF}/Grandia (Disc 1).chd.config"
run "${S}/roms/saturn/Grandia.m3u" saturn
expect "m3u first disc" '{"grandia":1}' "$(cat "${CONF}/Grandia (Disc 1).config")"
[ ! -e "${CONF}/Grandia.config" ] || fail "m3u config must not use the playlist name"
# The emulator still gets the playlist itself.
expect "m3u passed through" "[-r][3][-i][${S}/roms/saturn/Grandia.m3u]" "$(cat "${TMP}/out")"

# BIOS with spaces in its path stays one argument.
touch "${S}/roms/bios/my bios/saturn_bios.bin"
USE_HLE=1 run "${S}/roms/saturn/Game A.chd" saturn
expect "bios arg" "[-r][3][-i][${S}/roms/saturn/Game A.chd][-b][${S}/roms/bios/my bios/saturn_bios.bin]" "$(cat "${TMP}/out")"

# Exit codes: a real failure is passed on, a kill is not a failure.
STUB_RC=3 bash "${TMP}/start.sh" "${S}/roms/saturn/Game A.chd" saturn >/dev/null 2>&1
expect "failure passed on" "3" "$?"
STUB_RC=137 bash "${TMP}/start.sh" "${S}/roms/saturn/Game A.chd" saturn >/dev/null 2>&1
expect "kill is ok" "0" "$?"

[ "${FAILED}" = 0 ] && echo "start_yabasanshiro_test: all passed"
exit "${FAILED}"
