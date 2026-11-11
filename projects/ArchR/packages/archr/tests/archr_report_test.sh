#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-report: plants secrets in every place the report
# reads (configs, logs, pstore, command output, credential files) and
# proves none of them reaches the zip, while the useful facts (the SSID,
# the cores, the failed unit, hotkey settings) do. Fake commands on PATH;
# nothing real runs.
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
  "${R}/storage/.config/archr-launcher" "${R}/storage/.config/archr" "${R}/storage/.cache/iwd" \
  "${R}/var/log" "${R}/sys/fs/pstore" "${R}/usr/lib/libretro" "${R}/proc/device-tree" \
  "${R}/storage/roms" "${R}/etc"

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
input_enable_hotkey_btn = "nul"
keyboard_layout = "us"
hotkey_enable=1
EOF
echo "Passphrase=SECRET-iwd" >"${R}/storage/.cache/iwd/MinhaCasa.psk"
printf 'Running: retroarch -L core.so\nlogin user=foo SessionId=SECRET-session done\n' >"${R}/var/log/exec.log"
# NUL bytes and a Latin-1 SSID: not "text", still filtered.
printf 'bin\000ary\nretroarch: password=SECRET-binary\nconnected to Caf\351 wifi.key=SECRET-latin1\n' >>"${R}/var/log/exec.log"
printf 'Game Console R36S\0password=SECRET-model' >"${R}/proc/device-tree/model"

# One secret per line (earlier reviews, N1-N13). Lines that leave a quote
# open after the name come last: they take the rest of the file.
cat >"${R}/var/log/archr-launcher-session.log" <<'EOF'
launcher: signed in, token: SECRET-launcherlog
GET https://api.screenscraper.fr/api2/jeuInfos.php?devid=SECRET-devid&devpassword=x&ssid=SECRET-ssuser&sspassword=y
GET https://retroachievements.org/dorequest.php?r=login&u=SECRET-rauser&t=SECRET-ratoken
https://ra/dorequest.php?r=login&u=bob&t=SECRET-tok&p=SECRET-pw
http://h?a=1&P=SECRET-upper&T=SECRET-uppert
GET http://h/api?pw=SECRET-urlpw&game=Zelda2
Authorization: Bearer SECRET-bearer
Authorization:Bearer SECRET-bearer2
BEARER   SECRET-bearer3
iwctl --passphrase SECRET-passphrase station wlan0 connect MinhaCasa
wpa_passphrase MyNet SECRET-wpa
GET https://bob:SECRET-urlpass@example.org/x and ftp://u:SECRET-ftp@h/
http://user:SECRET-at@h/a@b
http://h/path/user@x/SECRET-pathat
ssh://bob:SECRET-ssh@h:22
user:SECRET-noscheme@host
curl -u admin:SECRET-curl http://h
curl -pSECRET-attachedp h
curl -uadmin:SECRET-attachedu h
curl --user=a:SECRET-longuser h
curl --user a:SECRET-longuser2 h
mysql -h x -pSECRET-mysql
mysql --password=SECRET-mysql2
-p SECRET-dashp
a -P SECRET-bigp
a -U bob:SECRET-bigu
wget --http-user=bob --http-password=SECRET-wget
wget --ftp-password SECRET-wget2
x --pass SECRET-pass --token=SECRET-tok2 --api-key SECRET-apikey
mount -o username=bob,password=SECRET-mount //h/s
cifs credentials=SECRET-creds
smbpasswd SECRET-smb
cmd -p SECRET-shortp --verbose
PASS=abc;PASS2=SECRET-pass2
db.pass.word=SECRET-dbpass
passwd:   SECRET-passwd more
x=1 next passwd=a SECRET-midline words
ra_user=SECRET-rauser2&ra_token=SECRET-ratoken2
x=1 password=SECRET-tail secret
Senha=SECRET-senha
chave: SECRET-chave
OAuth SECRET-oauth
password:
  SECRET-nextline
[Security]
Passphrase
=SECRET-equalsline
middle line kept
archr-launcher-session[812]: Launcher exited with 134; a session log line kept
/usr/bin/archr-launcher-session: line 9: 55648 Aborted, a session path kept
curl -H "X-Api-Key: SECRET-apikeyheader" h
{"password": "a\"SECRET-escaped quote"}
{"token":"t","pw":"SECRET-pw2","pwd":"SECRET-pwd"}
  "key"   :   "SECRET-key k"
auth_token="SECRET-auth b"
api_key = 'SECRET-apikey2'
EOF
# Values over several lines: one per file, as each takes the rest of it.
multi() { printf '%b' "$2" >"${R}$1"; }
multi /var/log/runemu-debug.log 'before=1\n{"secret": {\n  "a": "x}y",\n  "b": "SECRET-n1"\n}}\nafter=1\n'
multi /var/log/wifictl.log '{"password": [\n  "p]q",\n  "SECRET-n2"\n]\n'
multi /var/log/boot.log 'key: [\n  SECRET-n3\n]\n'
multi /storage/.config/retroarch/retroarch-core-options.cfg 'token = "multi\nSECRET-n4"\n'
multi /storage/.config/archr-launcher/launcher.toml 'theme = "default"\nsecret: {\n  a: "}"\n  SECRET-n5\n}\n'
multi /storage/.config/archr/systems.cfg '{"auth": {\n  "user": "SECRET-n6"\n},\n"after": 1}\n'
# Accented text stays; a CRLF value line and private keys go.
printf 'Pok\303\251mon Caf\303\251 ok\ntoken\r\nSECRET-crlf\r\nnameserver 9.9.9.9\n' >"${R}/etc/resolv.conf"
printf 'oops\n-----BEGIN OPENSSH PRIVATE KEY-----\nSECRET-ssh\n-----END OPENSSH PRIVATE KEY-----\n' >"${R}/sys/fs/pstore/console-ramoops-0"
printf 'k\n-----BEGIN PGP PRIVATE KEY BLOCK-----\nSECRET-pgp\n' >"${R}/etc/os-release"
multi /storage/.config/retroarch/retroarch.cfg.bak "x pass='it\\\\'s SECRET-n7' end\nnameserver 1.1.1.1\n"
echo "Kernel panic - not syncing: secret_key=SECRET-pstore" >"${R}/sys/fs/pstore/dmesg-ramoops-0"
printf 'compressed\000SECRET-compressed' >"${R}/sys/fs/pstore/dmesg-ramoops-1.enc.z"
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
X=$(echo "${TMP}"/x/*)
check "no secret leaks" "$(grep -rao 'SECRET[^ "]*' "${X}" | sed "s#${X}/##")" ""
check "iwd file never copied" "$(grep -rl 'Passphrase=SECRET' "${X}")" ""
check "compressed pstore left out" "$(find "${X}" -name '*.enc.z' | wc -l)" "0"
for want in MinhaCasa pcsx_rearmed_libretro.so archr-broken.service duckstation-sa \
  "R36S" 'video_driver = "gl"' "Kernel panic" "Running: retroarch" "kernel: normal line" \
  'input_enable_hotkey = "nul"' 'input_enable_hotkey_btn = "nul"' 'keyboard_layout = "us"' \
  "hotkey_enable=1" "middle line kept" "a session log line kept" "Aborted, a session path kept" "Caf" "Pok" "nameserver 9.9.9.9" "oops" "before=1" 'theme = "default"' "system.loglevel=verbose"; do
  if grep -raqF -- "${want}" "${X}"; then echo "ok   keeps ${want}"; else echo "FAIL lost ${want}"; FAILED=1; fi
done
# Named secrets keep their name; other hints take the whole line.
line() { grep -ah -- "$1" "${X}/$2" | head -1; }
check "name kept, value gone" "$(line '^root.password' configs/system.cfg)" "root.password=<removed>"
check "value with blanks" "$(line '^wifi.key' configs/system.cfg)" "wifi.key=<removed>"
check "quoted value" "$(line '^cheevos_password' configs/retroarch.cfg)" "cheevos_password=<removed>"
check "bearer" "$(line '^Authorization=' logs/launcher.log)" "Authorization=<removed>"
check "URL user:password" "$(line 'example.org\|^<linha' logs/launcher.log)" "<linha removida>"
# The X-Api-Key line closes its quotes: the escaped-quote line after it is
# cut on its own, then leaves a quote open and takes the rest.
check "every line of the log accounted for" "$(grep -c '' "${X}/logs/launcher.log")" "$(($(grep -c '' "${R}/var/log/archr-launcher-session.log") - 6 + 4))"
check "a value over lines takes the rest of the file" \
  "$(tr '\n' '|' <"${X}/logs/runemu-debug.log")" \
  '### /var/log/runemu-debug.log|before=1|{"secret=<removed>|<resto do arquivo removido>|'
check "private key takes the rest" "$(tail -n 1 "${X}/pstore/console-ramoops-0")" "<resto do arquivo removido>"
check "no temporary files left" "$(find "${R}/storage/roms/relatorios" -name '*.part' | wc -l)" "0"

# --osd: a card as it starts and one with the result; none without it.
fake archr-osd "echo \"\$*\" >>'${TMP}/osd'"
PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" >/dev/null
check "no card without --osd" "$(cat "${TMP}/osd" 2>/dev/null)" ""
OUT=$(PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" --osd)
check "--osd: same report" "$?:$(grep -c '^REPORT=' <<<"${OUT}")" "0:1"
check "--osd: start, then done" "$(tr '\n' '|' <"${TMP}/osd")" "send report start|send report done|"

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
rm -f "${TMP}/osd"
PATH="${TMP}/bin:${PATH}" ARCHR_REPORT_ROOT="${R}" bash "${SCRIPT}" --osd >/dev/null 2>&1
check "--osd: a failure says so" "$(tr '\n' '|' <"${TMP}/osd")" "send report start|send report failed|"
chmod 700 "${R}/storage/roms/relatorios"

# sanitize alone, line by line. A quote is open only when the whole line
# leaves it open: "$(cd ... && pwd)" closes on its own line, so the lines
# after it stay (a port script's first line took a whole report with it).
eval "$(sed -n '/^sanitize() {/,/^}/p' "${SCRIPT}")"
san() { printf '%s\n' "$@" | sanitize | tr '\n' '|'; }
# Nothing but ")\"" after the name reads as a value to come: the next line
# goes too, the ones after stay.
check "pwd in a closed command substitution keeps the rest of the file" \
  "$(san 'SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"' 'cd "$SCRIPT_DIR"' 'GAMEDIR=/roms/ports/pes6')" \
  'SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd=<removed>|<linha removida>|GAMEDIR=/roms/ports/pes6|'
check "a quoted name, value on the same line" \
  "$(san '"token" : "abc123"' 'next line')" \
  '"token=<removed>|next line|'
check "a quote left open still takes the rest" \
  "$(san 'password="abc' 'def"' 'after')" \
  'password=<removed>|<resto do arquivo removido>|'
check "an open single quote still takes the rest" \
  "$(san "cheevos_token = 'abc" "def'" 'after')" \
  'cheevos_token=<removed>|<resto do arquivo removido>|'
check "an open brace still takes the rest" \
  "$(san '{"secret": {' '"v": "x"}}' 'after')" \
  '{"secret=<removed>|<resto do arquivo removido>|'

exit ${FAILED}
