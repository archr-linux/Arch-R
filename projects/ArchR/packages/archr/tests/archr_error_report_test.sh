#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-error-report: the file name, one report per
# signature, the daily and queue limits, what the filter takes out (and
# what it keeps), the size cap, and the queue going out through a fake curl
# (sent, rate limited, refused, offline). Fake commands on PATH; nothing
# real is sent.
#   bash projects/ArchR/packages/archr/tests/archr_error_report_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="${HERE}/../sources/scripts"
SCRIPT="${SCRIPTS}/archr-error-report"
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
B="${TMP}/bin"
Q="${R}/storage/.cache/error-reports/queue"
S="${R}/storage/.cache/error-reports/sent"
mkdir -p "${B}" "${R}/storage/.config/system/configs" "${R}/storage/.config/retroarch" \
  "${R}/storage/.config/archr-launcher" "${R}/storage/.cache/iwd" "${R}/var/log" \
  "${R}/usr/share/archr" "${R}/proc/device-tree" "${R}/proc/sys/kernel" "${R}/etc" "${R}/tmp" "${R}/sys/fs/pstore"
CFG="${R}/storage/.config/system/configs/system.cfg"
cat >"${CFG}" <<'EOF'
global.retroachievements.username=RaHero
global.netplay.nickname=NetNick
system.loglevel=none
EOF
echo 'cheevos_username = "RaHero"' >"${R}/storage/.config/retroarch/retroarch.cfg"
printf 'user = "ScrapUser"\npassword = "x"\n' >"${R}/storage/.config/archr-launcher/scraper.toml"
: >"${R}/storage/.cache/iwd/MinhaCasa.psk"
# "Café 5G" as iwd writes a name it cannot keep: "=" and hex.
: >"${R}/storage/.cache/iwd/=436166c3a9203547.psk"
echo archr-f01b >"${R}/proc/sys/kernel/hostname"
printf 'Game Console R36S\0' >"${R}/proc/device-tree/model"
printf 'VERSION="20261110"\nBUILD_ID="0123456789abcdef"\nOS_BUILD="community"\n' >"${R}/etc/os-release"
cat >"${R}/usr/share/archr/systems.cfg" <<'EOF'
  <system>
    <name>n64</name>
    <fullname>Nintendo 64</fullname>
EOF
echo 'video_driver = "gl"' >"${R}/tmp/.retroarch.cfg"

fake() { printf '#!/bin/bash\n%s\n' "$2" >"${B}/$1"; chmod +x "${B}/$1"; }
fake archr-report "ARCHR_REPORT_ROOT='${R}' exec bash '${SCRIPTS}/archr-report' \"\$@\""
fake pacman 'echo "archr 20261110-1"; echo "archr-launcher 1:0.git-1"; echo "query: $*"'
fake dmesg 'cat "'"${TMP}"'/dmesg" 2>/dev/null'
fake journalctl 'cat "'"${TMP}"'/journal" 2>/dev/null'
fake systemctl 'printf "Result=exit-code\nExecMainCode=1\nExecMainStatus=1\nNRestarts=0\nFragmentPath=/usr/lib/systemd/system/archr-x.service\n"'
fake ip 'cat "'"${TMP}"'/route" 2>/dev/null'
fake gpudriver 'echo libmali'
# curl answers with the code in ${TMP}/code and keeps each upload.
fake curl 'url=${!#}; for a; do case "$p" in --data-binary) cp "${a#@}" "'"${TMP}"'/uploads/${url##*/}";; esac; p=$a; done; cat "'"${TMP}"'/code"'
mkdir -p "${TMP}/uploads"

report() { PATH="${B}:${PATH}" ARCHR_ERROR_REPORT_ROUTE_WAIT=1 ARCHR_ERROR_REPORT_ROOT="${R}" ARCHR_ERROR_REPORT_URL="https://test.invalid/api" bash "${SCRIPT}" "$@" 2>>"${TMP}/err"; }
count() { find "$1" -name '*.txt' 2>/dev/null | wc -l; }
# A game run: its output after OFFSET in exec.log.
game() {
  printf 'old run: error in another game\n' >"${R}/var/log/exec.log"
  local offset
  offset=$(stat -c %s "${R}/var/log/exec.log")
  printf '%b' "$2" >>"${R}/var/log/exec.log"
  report game "$1" 42 "${offset}" n64 retroarch mupen64plus_next -- "/storage/roms/n64/${3:-Super Mario 64 (USA).z64}" -Pn64 --core=mupen64plus_next --emulator=retroarch
}

# --- a crash: one report, named by date and time ---
cat >"${TMP}/dmesg" <<'EOF'
[ 12.5] retroarch[812]: unhandled exception: pc 0x0000007f8a1b2c3d in mupen64plus_next_libretro.so[7f8a000000+400000]
[ 12.6] wlan0: connected to bc:1a:e4:63:12:5b, address 192.168.3.10 fe80::be1a:e4ff:fe63:125b%wlan0
EOF
game 139 'Core: Loading 8MB RDRAM\nConnected to RaHero on 10.0.0.7 ssid=MinhaCasa\nVideo: texture cache full\nSegmentation fault at 0x7f8a1b2c\n'
check "one report queued" "$(count "${Q}")" "1"
F=$(find "${Q}" -name '*.txt' | head -n 1)
N=${F##*/}
if [[ "${N}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.txt$ ]]; then echo "ok   name ${N}"; else echo "FAIL name ${N}"; FAILED=1; fi
field() { sed -n "s/^$1: //p" "${F}" | head -n 1; }
check "event" "$(field event)" "game"
check "what" "$(field what)" "retroarch/mupen64plus_next"
check "system with its name" "$(field system)" "n64 (Nintendo 64)"
check "game kept (games are public)" "$(field game)" "Super Mario 64 (USA).z64"
check "exit with the signal and the time" "$(field exit)" "139 (SIGSEGV) after 42 s"
for want in "--- run output" "Segmentation fault" "unhandled exception" "device: Game Console R36S" \
  "archr: 20261110" "gpu: libmali" 'video_driver = "gl"' "query: -Qo /usr/bin/retroarch" "--- command ---"; do
  if grep -qF -- "${want}" "${F}"; then echo "ok   has ${want}"; else echo "FAIL lacks ${want}"; FAILED=1; fi
done
check "the command, whole" "$(sed -n '/^--- command ---$/{n;p}' "${F}")" "runemu.sh '/storage/roms/n64/Super Mario 64 (USA).z64' '-Pn64' '--core=mupen64plus_next' '--emulator=retroarch'"
check "only this run's output" "$(grep -c 'old run' "${F}")" "0"
check "no personal data" "$(grep -oiE 'RaHero|NetNick|ScrapUser|MinhaCasa|Caf.? 5G|archr-f01b|192\.168\.3\.10|10\.0\.0\.7|bc:1a:e4|fe80::' "${F}" | sort -u | tr '\n' ' ')" ""
check "addresses marked" "$(grep -c '<ip>' "${F}") $(grep -c '<mac>' "${F}")" "2 1"

# --- the same crash again: counted, not queued ---
game 139 'Core: Loading 8MB RDRAM\nVideo: texture cache full\nSegmentation fault at 0x7f00ffff\n'
check "repeat not queued" "$(count "${Q}")" "1"
check "repeat counted" "$(awk '{print $2}' "${R}/storage/.cache/error-reports/seen")" "2"

# --- exits from outside are not errors; an OOM kill is ---
game 143 'Terminated\n' 'other.z64'
game 137 'Killed\n' 'other.z64'
check "TERM and KILL ignored" "$(count "${Q}")" "1"
echo "[ 99.0] Out of memory: Killed process 900 (retroarch)" >>"${TMP}/dmesg"
game 137 'Killed\n' 'other.z64'
check "OOM kill reported" "$(count "${Q}")" "2"

# --- a failed service, the kernel, the launcher, a module ---
printf 'archr-x: starting\narchr-x: error: cannot open /dev/foo (code 5)\n' >"${TMP}/journal"
report unit archr-x.service
report unit archr-error-report-game-1.service
report unit archr-mod-weather.service
fake systemctl 'printf "Result=success\nExecMainStatus=0\n"'
report unit iwd.service
fake systemctl 'printf "Result=exit-code\nExecMainCode=1\nExecMainStatus=1\nNRestarts=0\nFragmentPath=/usr/lib/systemd/system/archr-x.service\n"'
check "unit reported; own, module and recovered units skipped" "$(count "${Q}")" "3"
check "the unit is what failed" "$(grep -h '^what: archr-x' "${Q}"/*.txt)" "what: archr-x.service"
printf 'Unable to handle kernel NULL pointer dereference at virtual address 0000000000000008\npc : panfrost_job_run+0x24/0x1a0\n' \
  >"${R}/sys/fs/pstore/dmesg-ramoops-0"
report kernel
report kernel
check "kernel oops reported once" "$(count "${Q}")" "4"
printf "thread 'main' panicked at src/main.rs:10:5\n" >"${TMP}/journal"
report launcher 101
check "launcher crash" "$(count "${Q}")" "5"
report module ../x 1
check "a bad module id is refused" "$(count "${Q}")" "5"

# --- the daily limit: 10 created a day ---
for n in 1 2 3 4 5 6 7; do game 1 "error: case ${n}${n}${n}x\n" "g${n}.z64"; done
check "ten a day" "$(count "${Q}")" "10"
check "today's count" "$(cut -d' ' -f2 "${R}/storage/.cache/error-reports/today")" "10"

# --- size cap: 256 KB ---
echo "$(date +%F) 0 0" >"${R}/storage/.cache/error-reports/today"
rm -f "${Q}"/*.txt
game 1 "error: big\n$(head -c 400000 /dev/zero | tr '\0' 'x' | fold -w 2000)\n" big.z64
F=$(find "${Q}" -name '*.txt' | head -n 1)
check "size capped" "$(($(stat -c %s "${F}") <= 262144))" "1"
check "cut marked" "$(tail -n 1 "${F}")" "[cut at 256 KB]"

# --- sending ---
for n in 1 2 3; do game 1 "error: send ${n}${n}x\n" "s${n}.z64"; sleep 1; done
check "four waiting" "$(count "${Q}")" "4"
echo 201 >"${TMP}/code"
report send
check "offline: nothing sent" "$(count "${Q}") $(ls "${TMP}/uploads" | wc -l)" "4 0"
echo "default via 192.168.3.1 dev wlan0" >"${TMP}/route"
echo 429 >"${TMP}/code"
report send
check "rate limited: all wait" "$(count "${Q}")" "4"
echo 000 >"${TMP}/code"
report send
check "no answer: all wait" "$(count "${Q}")" "4"
echo 400 >"${TMP}/code"
OLDEST=$(find "${Q}" -name '*.txt' | sort | head -n 1)
cp "${OLDEST}" "${TMP}/"
rm -f "${Q}"/*.txt && mv "${TMP}/${OLDEST##*/}" "${Q}/"
report send
check "refused: dropped" "$(count "${Q}")" "0"
check "refusal logged" "$(grep -c 'server refused' "${TMP}/err")" "1"
for n in 4 5 6; do game 1 "error: send ${n}${n}x\n" "s${n}.z64"; sleep 1; done
echo 201 >"${TMP}/code"
rm -f "${TMP}/uploads"/*
report send
check "sent: queue empty, three in sent" "$(count "${Q}") $(count "${S}")" "0 3"
U=$(ls "${TMP}/uploads" | head -n 1)
if [[ "${U}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}_[0-9a-f]{4}\.txt$ ]]; then echo "ok   upload name ${U}"; else echo "FAIL upload name ${U}"; FAILED=1; fi
check "upload is the queued text" "$(cmp -s "${TMP}/uploads/${U}" "${S}/${U%_*}.txt" && echo same)" "same"
check "sent today" "$(cut -d' ' -f3 "${R}/storage/.cache/error-reports/today")" "3"
# Ten sent a day at most: the rest waits for tomorrow.
echo "$(date +%F) 0 9" >"${R}/storage/.cache/error-reports/today"
for n in 7 8; do game 1 "error: send ${n}${n}x\n" "s${n}.z64"; sleep 1; done
report send
check "daily send limit" "$(count "${Q}") $(cut -d' ' -f3 "${R}/storage/.cache/error-reports/today")" "1 10"
# Only the last 20 sent stay.
for n in $(seq -w 1 25); do : >"${S}/2020-01-01_00-00-${n}.txt"; done
echo "$(date +%F) 0 0" >"${R}/storage/.cache/error-reports/today"
report send
check "sent kept: 20" "$(count "${S}")" "20"

# --- turned off: nothing new, the queue is dropped ---
game 1 'error: waiting\n' w.z64
echo "system.error_reports=0" >>"${CFG}"
before=$(count "${Q}")
game 1 'error: while off\n' off.z64
check "off: nothing queued" "$(count "${Q}")" "${before}"
report send
check "off: queue dropped" "$(count "${Q}")" "0"

# --- ports: the output decides, whatever the script returned ---
sed -i '/^system.error_reports=/d' "${CFG}"
rm -rf "${R}/storage/.cache/error-reports"
P="${R}/storage/roms/ports"
mkdir -p "${P}/asteroludi" "${P}/PortMaster/libs"
echo 2026.04.01-1426 >"${P}/PortMaster/version"
: >"${P}/PortMaster/control.txt"
cat >"${P}/Asteroludi.sh" <<'EOF'
#!/bin/bash
source $controlfolder/control.txt
GAMEDIR=/$directory/ports/asteroludi
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
$GPTOKEYB "arcajs" &
"./arcajs.${DEVICE_ARCH}" -f asteroludi.ajs
EOF
cat >"${P}/asteroludi/port.json" <<'EOF'
{"version": 4, "name": "asteroludi.zip", "items": ["Asteroludi.sh", "asteroludi/"],
 "attr": {"title": "Asteroludi", "porter": ["eludi"], "runtime": ["frt_3.5.2", "mono-6.12"], "arch": ["aarch64"]},
 "status": {"source": "PortMaster", "md5": "07f4"}}
EOF
printf '<gameList><game><name>asteroludi</name></game></gameList>\n' >"${P}/asteroludi/gameinfo.xml"
: >"${P}/PortMaster/libs/mono-6.12.squashfs"
{ printf '\177ELF'; head -c 2000 /dev/zero; } >"${P}/asteroludi/arcajs.aarch64"
echo "Error: game log line" >"${P}/asteroludi/log.txt"
fake ldd 'echo "	libcurl.so.4 => /usr/lib/libcurl.so.4"; echo "	libSDL2_gfx-1.0.so.0 => not found"'
fake gpudriver 'echo panfrost'
: >"${TMP}/dmesg"
# What the real Asteroludi prints on a good run (R36S, 2026-11-10).
NOISE='/roms/ports/PortMaster/device_info.txt: line 189: warning: command substitution: ignored null byte in input
CFW_NAME=ArchR
DEVICE_NAME=R36S
DISPLAY_WIDTH=640
./arcajs.aarch64: /usr/lib/libcurl.so.4: no version information available (required by ./arcajs.aarch64)
Attempting to fullscreen app_id=arcajs.aarch64
    "success": false,
    "parse_error": false,
    "error": "No matching node."
r36s_Gamepad :: 19003982010000008811000088010000
Failed, waiting to try again
localStorage load file "/storage/.local/share/eludi/arcajs/asteroludi.json" error: Couldn'"'"'t open /storage/.local/share/eludi/arcajs/asteroludi.json: No such file or directory
(<unknown>:610135): Gtk-WARNING **: 10:39:18.965: gtk_disable_setlocale() must be called before gtk_init()
arm_release_ver: g24p0-00eac0, rk_so_ver: 10
WARN: WindowControllerOpen(0): already opened'
port() {
  printf 'old run: Segmentation fault\n' >"${R}/var/log/exec.log"
  local offset
  offset=$(stat -c %s "${R}/var/log/exec.log")
  printf '%s\n' "$3" >>"${R}/var/log/exec.log"
  report port "$1" "$2" "${offset}" /storage/roms/ports/Asteroludi.sh -- /storage/roms/ports/Asteroludi.sh -Pports
}
port 0 40 "${NOISE}"
port 0 2 "${NOISE}"
check "a good run's noise is no failure, long or short" "$(count "${Q}")" "0"
port 143 40 "${NOISE}"
port 0 40 "${NOISE}
/storage/roms/ports/Asteroludi.sh: line 6: 4242 Killed  ./arcajs.aarch64 -f asteroludi.ajs"
check "TERM and a Killed without OOM are the user's" "$(count "${Q}")" "0"
port 0 3 "${NOISE}
Error: no game data"
check "an error line on a short run counts" "$(count "${Q}")" "1"
port 0 60 "${NOISE}
Error: no game data, again"
check "the same line on a long run does not" "$(count "${Q}")" "1"
rm -f "${Q}"/*.txt
# The PortMaster bug of 2026-11-10: control.txt missing; the script still
# exits 0.
port 0 1 "/roms/ports/Asteroludi.sh: line 2: /roms/ports/PortMaster/control.txt: No such file or directory
/roms/ports/Asteroludi.sh: line 6: ./arcajs.: No such file or directory"
check "script errors with exit 0 are reported" "$(count "${Q}")" "1"
F=$(find "${Q}" -name '*.txt' | head -n 1)
check "event" "$(field event)" "port"
check "what: the port's title" "$(field what)" "Asteroludi"
check "game: the script" "$(field game)" "Asteroludi.sh"
check "only the failure lines" "$(sed -n '/^--- failure lines ---$/,/^$/p' "${F}" | wc -l)" "4"
check "failure lines come first" "$(sed -n '/^--- failure lines ---$/{n;p}' "${F}")" \
  "/roms/ports/Asteroludi.sh: line 2: /roms/ports/PortMaster/control.txt: No such file or directory"
for want in "porter: eludi" "runtime: frt_3.5.2, mono-6.12" "runtime frt_3.5.2: MISSING from PortMaster/libs" \
  "runtime mono-6.12: present" "portmaster: 2026.04.01-1426" "gameinfo name: asteroludi" \
  "arcajs.aarch64: 	libSDL2_gfx-1.0.so.0 => not found" "gptokeyb: used by the script, no .gptk in the folder" \
  "gpu: panfrost" "--- script (first 80 lines) ---" "--- port log log.txt (last 80 lines) ---" \
  "(the script tees it: same as the run output)"; do
  if grep -qF -- "${want}" "${F}"; then echo "ok   has ${want}"; else echo "FAIL lacks ${want}"; FAILED=1; fi
done
check "libraries found are left out" "$(grep -c 'libcurl.so.4 =>' "${F}")" "0"
# The same failure on another console (other paths and numbers): counted.
port 0 1 "/storage/roms/ports/Asteroludi.sh: line 2: /storage/roms/ports/PortMaster/control.txt: No such file or directory"
check "signature ignores paths and numbers" "$(count "${Q}")" "1"
for line in "Segmentation fault (core dumped)" "./arcajs.aarch64: error while loading shared libraries: libSDL2.so: cannot open shared object file" \
  "Traceback (most recent call last):" "Error: [string \"main.lua\"]:12: attempt to call nil" "SDL_CreateWindow failed: Could not initialize EGL" \
  "Unhandled Exception: System.DllNotFoundException: libSDL2" "box64: Error loading needed lib libGL.so.1" "FATAL: no GPU"; do
  rm -f "${Q}"/*.txt "${R}/storage/.cache/error-reports/"{seen,today}
  port 0 120 "${NOISE}
${line}"
  check "marker: ${line}" "$(count "${Q}")" "1"
done
# A port that writes its own log and nothing to exec.log (NextOS ports):
# the failure lines come from that log.
mkdir -p "${P}/chrono"
cat >"${P}/Chrono Trigger.sh" <<'EOF'
#!/bin/bash
GAMEDIR="/$directory/ports/chrono"
exec > "$GAMEDIR/log.txt" 2>&1
EOF
printf '{"version": 4, "name": "chrono.zip", "items": ["Chrono Trigger.sh", "chrono/"], "attr": {"title": "Chrono Trigger"}}\n' >"${P}/chrono/port.json"
nxport() {
  printf '%s\n' "$3" >"${P}/chrono/log.txt"
  local offset
  offset=$(stat -c %s "${R}/var/log/exec.log")
  report port "$1" "$2" "${offset}" "/storage/roms/ports/Chrono Trigger.sh" -- "/storage/roms/ports/Chrono Trigger.sh" -Pports
}
rm -f "${Q:?}"/*.txt "${R:?}/storage/.cache/error-reports/seen" "${R:?}/storage/.cache/error-reports/today"
nxport 1 13 '== Chrono Trigger | nxbootstrap 0.6.17 | cfw=ArchR ==
[2026-11-11 12:46:48] TERMINAL ERROR NXE2001: no APK, APKM, APKS, XAPK, companion archive or loose payload was found
ERROR: game data installation did not complete'
check "NextOS port with no game data: an answer, no report" "$(count "${Q}")" "0"
nxport 1 12 '[2026-11-11 12:53:44] ERROR: no APK, APKM, APKS, XAPK, companion archive or loose payload was found
ERROR: game data installation did not complete'
check "the same from NXExtract 1.2.6 (no code)" "$(count "${Q}")" "0"
nxport 1 13 '[2026-11-11 12:46:48] TERMINAL ERROR NXE6001: [Errno 1] Operation not permitted'
check "NextOS port failing for another reason is reported" "$(count "${Q}")" "1"
F=$(find "${Q}" -name '*.txt' | head -n 1)
check "its own log gives the failure line" "$(sed -n '/^--- failure lines ---$/{n;p}' "${F}")" \
  "[2026-11-11 12:46:48] TERMINAL ERROR NXE6001: [Errno 1] Operation not permitted"
check "and is attached" "$(grep -c '^--- port log log.txt (last 80 lines) ---$' "${F}")" "1"
rm -f "${Q:?}"/*.txt "${R:?}/storage/.cache/error-reports/seen" "${R:?}/storage/.cache/error-reports/today"
nxport 2 18 '[subsurf] frame 4 keep=0
[subsurf] signal 11 at pc=0xffff85e8cd64 addr=0x1'
check "a crash only the port's log tells is reported" "$(sed -n '/^--- failure lines ---$/{n;p}' "$(find "${Q}" -name '*.txt' | head -n 1)")" \
  "[subsurf] signal 11 at pc=0xffff85e8cd64 addr=0x1"

# NetSurf's missing translation is no failure, even with exit 0 after a
# session of browsing (2026-11-12).
rm -f "${Q:?}"/*.txt "${R:?}/storage/.cache/error-reports/seen" "${R:?}/storage/.cache/error-reports/today"
port 0 330 "${NOISE}
Message translations failed to load"
check "NetSurf's translation line is noise" "$(count "${Q}")" "0"

# --- games: a program the user copies in, the command whole ---
pico() {
  printf 'old run: error\n' >"${R}/var/log/exec.log"
  local offset
  offset=$(stat -c %s "${R}/var/log/exec.log")
  printf '%b' "$2" >>"${R}/var/log/exec.log"
  report game "$1" 1 "${offset}" pico-8 pico8 pico8 -- /storage/roms/pico-8/Splore.png -Ppico-8 --core=pico8 --emulator=pico8 \
    '--controllers= -p1index 0 -p1guid 19003982010000008811000088010000 '
}
pico 127 "chmod: cannot access '/storage/roms/pico-8//pico8_64': No such file or directory\n/usr/bin/start_pico8.sh: line 48: /storage/roms/pico-8//pico8_64: No such file or directory\n"
check "PICO-8 without its program: the user's to add, no report" "$(count "${Q}")" "0"
pico 1 'error: cart failed\n'
check "PICO-8 failing otherwise is reported" "$(count "${Q}")" "1"
F=$(find "${Q}" -name '*.txt' | head -n 1)
check "its command keeps the controller options" "$(sed -n '/^--- command ---$/{n;p}' "${F}")" \
  "runemu.sh '/storage/roms/pico-8/Splore.png' '-Ppico-8' '--core=pico8' '--emulator=pico8' '--controllers= -p1index 0 -p1guid 19003982010000008811000088010000 '"

# --- the launcher with no screen yet: a report only if none comes ---
mkdir -p "${R}/run" "${R}/sys/class/drm/card0-DSI-1"
echo disconnected >"${R}/sys/class/drm/card0-DSI-1/status"
rm -f "${Q:?}"/*.txt "${R:?}/storage/.cache/error-reports/seen" "${R:?}/storage/.cache/error-reports/today"
printf '[ 51.2] host archr-launcher-session[3491]: archr-launcher: The video driver did not add any displays\n' >"${TMP}/journal"
fake swaymsg 'printf "[\n  {\n    \"name\": \"DSI-1\",\n    \"active\": true\n  }\n]\n"'
ARCHR_ERROR_REPORT_DISPLAY_WAIT=1 report launcher 1
check "a screen that comes late: no report" "$(count "${Q}")" "0"
fake swaymsg 'printf "[]\n"'
ARCHR_ERROR_REPORT_DISPLAY_WAIT=1 report launcher 1
check "no screen at all: reported" "$(count "${Q}")" "1"
F=$(find "${Q}" -name '*.txt' | head -n 1)
check "with the connectors" "$(grep -c '^card0-DSI-1/status: disconnected$' "${F}")" "1"
exec 8>"${R}/run/archr-error-report.display" && flock -n 8
rm -f "${Q:?}"/*.txt "${R:?}/storage/.cache/error-reports/seen"
ARCHR_ERROR_REPORT_DISPLAY_WAIT=1 report launcher 1
check "while one reporter waits, the session's next tries leave it to it" "$(count "${Q}")" "0"
exec 8>&-

eval "$(sed -n '/^normalize() {/,/^}/p' "${SCRIPT}")"
check "a signature line keeps file names, not paths or numbers" \
  "$(normalize <<<'Segmentation fault at /a/b/c.so 0x12 pid 77')" "Segmentation fault at c.so # pid #"

# runemu.sh: every port run goes to the reporter (it decides), other games
# only when they exit with an error.
BLOCK=$(sed -n "/^### A port's script usually exits 0/,/^fi$/p" "${SCRIPTS}/runemu.sh")
runemu_report() {
  local PLATFORM=$1 ret_error=$2 ROMNAME=/storage/roms/ports/A.sh EMULATOR=x CORE=y RUN_OFFSET=10 RUN_START=0 SECONDS=7
  local ARGV=("${ROMNAME}" -Pports)
  get_setting() { echo 1; }
  : >"${TMP}/runs"
  PATH="${B}:${PATH}" eval "${BLOCK}"
  sed 's/^.*archr-error-report //' "${TMP}/runs"
}
fake systemd-run 'echo "$*" >>"'"${TMP}"'/runs"'
check "runemu: a port that exited 0 still goes" "$(runemu_report ports 0)" "port 0 7 10 /storage/roms/ports/A.sh -- /storage/roms/ports/A.sh -Pports"
check "runemu: a game that exited 0 does not" "$(runemu_report gb 0)" ""
check "runemu: a game that failed does" "$(runemu_report gb 139)" "game 139 7 10 gb x y -- /storage/roms/ports/A.sh -Pports"

exit ${FAILED}
