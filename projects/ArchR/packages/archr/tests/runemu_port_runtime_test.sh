#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

# Host test for runemu.sh port_runtime_ready: the runtimes a port names
# (port.json "runtime", the script's <x>runtime="name" with a
# libs/<name>.squashfs, or that path itself) are fetched with harbourmaster
# when missing and online; offline the port does not start and a toast, in
# the system language, says what it needs. A fake PortMaster folder and a
# fake harbourmaster; nothing is downloaded.
#   bash projects/ArchR/packages/archr/tests/runemu_port_runtime_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="${HERE}/../sources/scripts"
RUNEMU="${SCRIPTS}/runemu.sh"
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
if bash -n "${RUNEMU}"; then echo "ok   bash -n"; else echo "FAIL bash -n"; FAILED=1; fi

eval "$(sed -n '/^function port_dir() {/,/^}/p; /^function port_runtimes() {/,/^}/p;
  /^function prep_run() {/,/^}/p; /^function prep_end() {/,/^}/p;
  /^function port_runtime_present() {/,/^}/p; /^function port_runtime_broken() {/,/^}/p;
  /^function port_title() {/,/^}/p;
  /^function port_runtime_ready() {/,/^}/p' "${RUNEMU}")"
log() { :; }
LANGUAGE_SETTING=""
get_setting() { [ "$1" = system.language ] && echo "${LANGUAGE_SETTING}"; }
ONLINE=1
online() { [ "${ONLINE}" = 1 ]; }
AMIONLINE=online
OUTPUT_LOG="${TMP}/exec.log"
PORTS="${TMP}/ports"
PM_DIR="${PORTS}/PortMaster"
export ARCHR_TOAST_DIR="${TMP}/notify"
PATH="${SCRIPTS}:${PATH}"
mkdir -p "${PM_DIR}/libs" "${PM_DIR}/runtimes"
# harbourmaster records what it was asked for and "installs" it.
cat >"${PM_DIR}/harbourmaster" <<EOF
#!/bin/bash
echo "\${@: -1}" >>"${TMP}/fetched"
[ -e "${TMP}/unknown" ] && exit 255
{ printf 'hsqs'; head -c 36 /dev/zero; printf '\\x60\\0\\0\\0\\0\\0\\0\\0'; head -c 48 /dev/zero; } >"libs/\${@: -1}"
EOF
chmod +x "${PM_DIR}/harbourmaster"
# sqfs FILE USED SIZE: a squashfs superblock saying USED bytes, in a file of SIZE.
sqfs() {
  { printf 'hsqs'; head -c 36 /dev/zero; printf "$(printf '%016x' "$2" | sed -E 's/(..)(..)(..)(..)(..)(..)(..)(..)/\\x\8\\x\7\\x\6\\x\5\\x\4\\x\3\\x\2\\x\1/')"
    head -c $(($3 - 48)) /dev/zero; } >"$1"
}

toast() {
  local f out=""
  for f in "${ARCHR_TOAST_DIR}"/*.toast; do
    [ -f "${f}" ] && out+="$(tr '\n' '|' <"${f}")"
  done
  rm -rf "${ARCHR_TOAST_DIR}"
  echo "${out}"
}
fetched() { cat "${TMP}/fetched" 2>/dev/null | tr '\n' ' '; rm -f "${TMP}/fetched"; }
# ready SCRIPT: "0" or "1", what was fetched, the toast
ready() {
  local rc
  port_runtime_ready "${PORTS}/$1"
  rc=$?
  echo "${rc} [$(fetched)] $(toast)"
}

# A catalog port: port.json names the runtimes.
mkdir -p "${PORTS}/timespinner"
printf '#!/bin/bash\nGAMEDIR=/$directory/ports/timespinner\nmono Timespinner.exe\n' >"${PORTS}/Timespinner.sh"
printf '{"items": ["Timespinner.sh", "timespinner/"], "attr": {"title": "Timespinner", "runtime": ["mono-6.12.0.122-aarch64"]}}\n' \
  >"${PORTS}/timespinner/port.json"
check "online: the missing runtime is fetched, the port starts" "$(ready Timespinner.sh)" \
  "0 [mono-6.12.0.122-aarch64.squashfs ] "
check "then it is there: nothing fetched" "$(ready Timespinner.sh)" "0 [] "

# A dArkOS-style script with no port.json: runtime="..." and its libs path.
mkdir -p "${PORTS}/frtgame"
cat >"${PORTS}/Frt Game.sh" <<'EOF'
#!/bin/bash
GAMEDIR="/$directory/ports/frtgame"
runtime="frt_3.5.2"
if [ ! -f "$controlfolder/libs/${runtime}.squashfs" ]; then
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${runtime}.squashfs"
fi
weston_runtime="weston_pkg_0.2"
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
EOF
ONLINE=0
check "offline: not started, a toast says what it needs" "$(ready "Frt Game.sh")" \
  "1 [] error|errors|Frt Game needs frt_3.5.2 weston_pkg_0.2|Connect to the internet once to download it|"
LANGUAGE_SETTING=pt_BR
check "in the system language" "$(ready "Frt Game.sh")" \
  "1 [] error|errors|Frt Game precisa de frt_3.5.2 weston_pkg_0.2|Conecte à internet uma vez para baixar|"
LANGUAGE_SETTING=""
ONLINE=1
check "online: both fetched" "$(ready "Frt Game.sh")" "0 [frt_3.5.2.squashfs weston_pkg_0.2.squashfs ] "

# A literal libs path (an old mono port), and a runtime kept as a folder.
printf '#!/bin/bash\nmonofile=$controlfolder/libs/mono-5.0-aarch64.squashfs\nruntime="love_11.5"\n' >"${PORTS}/Old Mono.sh"
: >"${TMP}/unknown"
check "a runtime harbourmaster does not know: the port starts anyway" "$(ready "Old Mono.sh")" \
  "0 [love_11.5.squashfs mono-5.0-aarch64.squashfs ] "
rm -f "${TMP}/unknown"
mkdir -p "${PM_DIR}/runtimes/love_11.5"
sqfs "${PM_DIR}/libs/mono-5.0-aarch64.squashfs" 96 96
ONLINE=0
check "a runtime kept as a folder counts as there" "$(ready "Old Mono.sh")" "0 [] "

# runtime= in a script that mounts nothing from libs: not a PortMaster runtime.
printf '#!/bin/bash\nruntime="java"\n./run.sh\n' >"${PORTS}/Plain.sh"
check "no libs/*.squashfs in the script: nothing asked" "$(ready Plain.sh)" "0 [] "
check "a port with no runtime at all" "$(printf '#!/bin/bash\n./game\n' >"${PORTS}/Game.sh"; ready Game.sh)" "0 [] "

# A runtime cut short (MOMO's python_3.11, 20 of 33 MB): removed and fetched again.
sqfs "${PM_DIR}/libs/love_11.5.squashfs" 4096 1024
rm -rf "${PM_DIR}/runtimes/love_11.5"
ONLINE=1
check "a runtime cut short is fetched again" "$(ready "Old Mono.sh")" "0 [love_11.5.squashfs ] "
check "and the new one is whole" "$(port_runtime_broken love_11.5 && echo broken || echo whole)" "whole"
sqfs "${PM_DIR}/libs/love_11.5.squashfs" 4096 1024
ONLINE=0
check "offline: a runtime cut short stops the port, as a missing one" "$(ready "Old Mono.sh")" \
  "1 [] error|errors|Old Mono needs love_11.5|Connect to the internet once to download it|"
printf 'not a squashfs' >"${PM_DIR}/libs/frt_3.5.2.squashfs"
check "a file that is no squashfs is broken" "$(port_runtime_broken frt_3.5.2 && echo broken)" "broken"
sqfs "${PM_DIR}/libs/frt_3.5.2.squashfs" 4096 8192
check "a padded whole one is not" "$(port_runtime_broken frt_3.5.2 || echo whole)" "whole"
exit "${FAILED}"
