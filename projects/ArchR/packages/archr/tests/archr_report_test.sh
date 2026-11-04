#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-report: plants secrets in every place the report
# reads (configs, logs, pstore, command output, credential files) and
# proves none of them reaches the zip, while the useful facts (the SSID,
# the cores, the failed unit) do. Fake commands on PATH; nothing real runs.
#   bash projects/ArchR/packages/archr/tests/archr_report_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${HERE}/../sources/scripts/archr-report"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "     got:      $2"
    echo "     expected: $3"
    FAILED=1
  fi
}

if bash -n "${SCRIPT}"; then echo "ok   bash -n"; else echo "FAIL bash -n"; FAILED=1; fi

R="${TMP}/root"
mkdir -p "${TMP}/bin" "${R}/storage/.config/system/configs" "${R}/storage/.config/retroarch" \
  "${R}/storage/.config/archr-launcher" "${R}/storage/.cache/iwd" "${R}/var/log" \
  "${R}/sys/fs/pstore" "${R}/usr/lib/libretro" "${R}/proc/device-tree" "${R}/storage/roms"

# Every secret carries SECRET so one grep finds a leak.
cat >"${R}/storage/.config/system/configs/system.cfg" <<'EOF'
wifi.ssid=MinhaCasa
wifi.key=SECRET-wifi with spaces
root.password=abc;SECRET-semicolon
wifi.adhoc.key=a&SECRET-ampersand
global.retroachievements.username=SECRET-rauser
global.retroachievements.password=SECRET-rapass
global.retroachievements.token=SECRET-ratoken
scraper.screenscraper.username=SECRET-ssuser
scraper.screenscraper.password=SECRET-sspass
system.devpassword=SECRET-dev
system.loglevel=verbose
EOF
cat >"${R}/storage/.config/retroarch/retroarch.cfg" <<'EOF'
cheevos_username = "SECRET-cheevosuser"
cheevos_password = "SECRET with spaces"
cheevos_token = "SECRET-cheevostoken"
netplay_password = "SECRET-netplay"
video_driver = "gl"
input_enable_hotkey = "nul"
keyboard_layout = "us"
EOF
cat >"${R}/storage/.config/archr-launcher/launcher.toml" <<'EOF'
api_key = 'SECRET-apikey'
[store]
"auth_token": "SECRET-json"
theme = "default"
EOF
echo "Passphrase=SECRET-iwd" >"${R}/storage/.cache/iwd/MinhaCasa.psk"
printf 'Running: retroarch -L core.so\nlogin user=foo SessionId=SECRET-session done\n' >"${R}/var/log/exec.log"
cat >"${R}/var/log/archr-launcher-session.log" <<'EOF'
launcher: signed in, token: SECRET-launcherlog
GET https://api.screenscraper.fr/api2/jeuInfos.php?devid=SECRET-devid&devpassword=x&ssid=SECRET-ssuser&sspassword=y&romnom=Zelda
GET https://retroachievements.org/dorequest.php?r=login&u=SECRET-rauser&t=SECRET-ratoken
Authorization: Bearer SECRET-bearer
iwctl --passphrase SECRET-passphrase station wlan0 connect MinhaCasa
EOF
cat >>"${R}/var/log/archr-launcher-session.log" <<'EOF'
GET https://bob:SECRET-urlpass@example.org/x and ftp://u:SECRET-ftp@h/
curl -u admin:SECRET-curl http://h
cmd -p SECRET-shortp --verbose
{"password": "a\"SECRET-escaped quote"}
x pass='it\'s SECRET-single' end
{"token":"t","pw":"SECRET-pw","pwd":"SECRET-pwd"}
GET http://h/api?pw=SECRET-urlpw&game=Zelda2
x=1 next passwd=a SECRET-midline words
{"auth": {
  "user": "SECRET-nesteduser",
  "list": ["SECRET-nested1", "SECRET-nested2"]
},
"after_nested": 1}
EOF
# NUL bytes and a Latin-1 SSID: no longer "text", still filtered.
printf 'bin\000ary\nretroarch: password=SECRET-binary\nconnected to Caf\351 wifi.key=SECRET-latin1\n' >>"${R}/var/log/exec.log"
echo "Kernel panic - not syncing: secret_key=SECRET-pstore" >"${R}/sys/fs/pstore/dmesg-ramoops-0"
printf 'compressed\000SECRET-compressed' >"${R}/sys/fs/pstore/dmesg-ramoops-1.enc.z"
printf 'Game Console R36S\0password=SECRET-model' >"${R}/proc/device-tree/model"
touch "${R}/usr/lib/libretro/pcsx_rearmed_libretro.so"

fake() { printf '#!/bin/sh\n%s\n' "$2" >"${TMP}/bin/$1"; chmod +x "${TMP}/bin/$1"; }
fake journalctl 'case "$*" in *list-boots*) echo "  0 abc Fri"; echo " -1 def Thu";; *-b\ -1*) echo "previous boot psk=SECRET-prev";; *) echo "iwd: PreSharedKey: SECRET-journal"; echo "kernel: normal line";; esac'
fake dmesg 'echo "[1.0] rk817: ok Authorization: SECRET-dmesg"'
fake systemctl 'echo "archr-broken.service loaded failed failed"'
fake iwctl 'echo "Connected network MinhaCasa"'
fake pacman 'echo "retroarch 1.21.0-3"; echo "duckstation-sa 0.1-1"'
fake uname 'echo Linux archr 6.12.114'

OUT=$(PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}")
check "exit status" "$?" "0"
ZIP=$(sed -n 's/^REPORT=//p' <<<"${OUT}")
case "${ZIP}" in
  /storage/roms/relatorios/archr-relatorio-*.zip) echo "ok   path ${ZIP}" ;;
  *) echo "FAIL path ${ZIP}"; FAILED=1 ;;
esac
check "size printed" "$(sed -n 's/^SIZE=//p' <<<"${OUT}")" "$(stat -c %s "${R}${ZIP}")"

mkdir "${TMP}/x" && (cd "${TMP}/x" && unzip -q "${R}${ZIP}")
check "no secret leaks" "$(grep -rl SECRET "${TMP}/x" | sed "s#${TMP}/x/##")" ""
check "iwd file never copied" "$(grep -rl Passphrase "${TMP}/x")" ""
for want in MinhaCasa pcsx_rearmed_libretro.so archr-broken.service duckstation-sa \
  "R36S" "video_driver" "previous boot" "Kernel panic" "Running: retroarch" \
  'input_enable_hotkey = "nul"' 'keyboard_layout = "us"' "r=login" \
  "station wlan0 connect" "Caf" "example.org/x" "game=Zelda2" "after_nested" "cmd -p"; do
  if grep -rqF -- "${want}" "${TMP}/x"; then echo "ok   keeps ${want}"; else echo "FAIL lost ${want}"; FAILED=1; fi
done
check "names kept, values removed" \
  "$(grep -h '^root.password=' "${TMP}"/x/*/configs/system.cfg)" "root.password=<removed>"
check "unquoted value with blanks removed whole" \
  "$(grep -h '^wifi.key=' "${TMP}"/x/*/configs/system.cfg)" "wifi.key=<removed>"
check "URL fields" \
  "$(grep -ho 'u=[^&]*&t=.*' "${TMP}"/x/*/logs/launcher.log)" "u=<removed>&t=<removed>"
check "bearer token" "$(grep -h '^Authorization' "${TMP}"/x/*/logs/launcher.log)" "Authorization: <removed>"
check "compressed pstore left out" "$(find "${TMP}/x" -name '*.enc.z' | wc -l)" "0"
check "quoted value removed whole" \
  "$(grep -h '^cheevos_password' "${TMP}"/x/*/configs/retroarch.cfg)" 'cheevos_password = <removed>'
check "no temporary files left" "$(find "${R}/storage/roms/relatorios" -name '*.part' | wc -l)" "0"

check "URL user and password" \
  "$(grep -h '^GET https://' "${TMP}"/x/*/logs/launcher.log | grep -o '//[^ ]*example.org')" "//<removed>@example.org"
check "curl -u" "$(grep -h '^curl -u' "${TMP}"/x/*/logs/launcher.log)" "curl -u <removed> http://h"

# Nothing left to zip (every file failed the filter): exit 1, no report.
mkdir -p "${TMP}/broken"
printf '#!/bin/sh\nexit 1\n' >"${TMP}/broken/awk"
chmod +x "${TMP}/broken/awk"
before=$(find "${R}/storage/roms/relatorios" -name '*.zip' | wc -l)
OUT=$(PATH="${TMP}/broken:${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" 2>"${TMP}/err")
check "empty report fails" "$?:${OUT}" "1:"
check "says why" "$(grep -c 'no report written' "${TMP}/err")" "1"
check "no zip added" "$(find "${R}/storage/roms/relatorios" -name '*.zip' | wc -l)" "${before}"

# A folder that cannot be written: exit 1, nothing printed.
chmod 500 "${R}/storage/roms/relatorios"
OUT=$(PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" 2>/dev/null)
check "unwritable folder fails" "$?:${OUT}" "1:"
chmod 700 "${R}/storage/roms/relatorios"

exit ${FAILED}
