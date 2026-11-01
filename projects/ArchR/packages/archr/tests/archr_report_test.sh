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
wifi.key=SECRET-wifi
root.password=SECRET-root
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
EOF
cat >"${R}/storage/.config/archr-launcher/launcher.toml" <<'EOF'
api_key = 'SECRET-apikey'
[store]
"auth_token": "SECRET-json"
theme = "default"
EOF
echo "Passphrase=SECRET-iwd" >"${R}/storage/.cache/iwd/MinhaCasa.psk"
printf 'Running: retroarch -L core.so\nlogin user=foo SessionId=SECRET-session done\n' >"${R}/var/log/exec.log"
echo "launcher: signed in, token: SECRET-launcherlog" >"${R}/var/log/archr-launcher-session.log"
echo "Kernel panic - not syncing: secret_key=SECRET-pstore" >"${R}/sys/fs/pstore/dmesg-ramoops-0"
printf 'Game Console R36S\0' >"${R}/proc/device-tree/model"
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
  "R36S" "video_driver" "previous boot" "Kernel panic" "Running: retroarch"; do
  if grep -rqF -- "${want}" "${TMP}/x"; then echo "ok   keeps ${want}"; else echo "FAIL lost ${want}"; FAILED=1; fi
done
check "names kept, values removed" \
  "$(grep -h '^root.password=' "${TMP}"/x/*/configs/system.cfg)" "root.password=<removed>"
check "quoted value removed whole" \
  "$(grep -h '^cheevos_password' "${TMP}"/x/*/configs/retroarch.cfg)" 'cheevos_password = <removed>'
check "no temporary files left" "$(find "${R}/storage/roms/relatorios" -name '*.part' | wc -l)" "0"

# A folder that cannot be written: exit 1, nothing printed.
chmod 500 "${R}/storage/roms/relatorios"
OUT=$(PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" 2>/dev/null)
check "unwritable folder fails" "$?:${OUT}" "1:"
chmod 700 "${R}/storage/roms/relatorios"

exit ${FAILED}
