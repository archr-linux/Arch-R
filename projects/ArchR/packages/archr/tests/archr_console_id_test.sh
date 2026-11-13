#!/bin/bash
# Host test for archr-console-id: the OTP id (computed here on its own with
# sha256sum), each source left out when it holds nothing, the order of the
# sources, and the random id kept and reused.
#   bash projects/ArchR/packages/archr/tests/archr_console_id_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${HERE}/../sources/scripts/archr-console-id"
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
OTP="${R}/sys/bus/nvmem/devices/rockchip-otp0/nvmem"
KEPT="${R}/storage/.config/archr/console-id"
mkdir -p "${OTP%/*}" "${R}/proc/device-tree"
id() { ARCHR_CONSOLE_ID_ROOT="${R}" bash "${SCRIPT}" "$@"; }
expect() { { printf 'archr-console-id:v1:'; printf '%b' "$1"; } | sha256sum | cut -c1-12; }

# The R36S's OTP (and more bytes after the first 32, which do not count).
R36S='\x52\x4b\x33\x26\x91\xfe\x21\x55\x52\x4b\x43\x33\x35\x30\x30\x34\x00\x00\x00\x00\x12\x24\x0b\x06\x05\x00\x00\x00\x00\x00\x00\x00'
printf "${R36S}"'\x01\x02\x03' >"${OTP}"
check "otp: the hash of the first 32 bytes" "$(id)" "$(expect "${R36S}")"
check "otp: the R36S's id" "$(id)" "e119e1afb0fc"
check "otp: exit 0, one line" "$(id | wc -l):$?" "1:0"
check "otp: --source" "$(id --source)" "otp"
check "otp: the same on every run" "$(id)" "$(id)"
check "otp: nothing kept" "$([ -e "${KEPT}" ] && echo kept)" ""

# Bad OTP: the next source.
printf 'Game Console R36S\0' >"${R}/proc/device-tree/serial-number"
printf 'processor\t: 0\nSerial\t\t: 1a2b3c4d5e6f7788\n' >"${R}/proc/cpuinfo"
head -c 32 /dev/zero >"${OTP}"
check "all-zero otp: device-tree" "$(id --source) $(id)" "device-tree $(expect 'Game Console R36S')"
head -c 32 /dev/zero | tr '\0' '\377' >"${OTP}"
check "all-ff otp: device-tree" "$(id --source)" "device-tree"
printf "${R36S}" | head -c 31 >"${OTP}"
check "short otp: device-tree" "$(id --source)" "device-tree"
rm -f "${OTP}"
check "no otp: device-tree" "$(id --source)" "device-tree"

# Empty or zero serial-number: cpuinfo.
printf '0000000000000000\0' >"${R}/proc/device-tree/serial-number"
check "zero serial-number: cpuinfo" "$(id --source) $(id)" "cpuinfo $(expect 1a2b3c4d5e6f7788)"
printf '\0' >"${R}/proc/device-tree/serial-number"
check "empty serial-number: cpuinfo" "$(id --source)" "cpuinfo"

# Nothing in the hardware: a random id, kept and reused.
printf 'Serial\t\t: 0000000000000000\n' >"${R}/proc/cpuinfo"
first=$(id)
check "random: --source" "$(id --source)" "random"
if [[ "${first}" =~ ^[0-9a-f]{12}$ ]]; then echo "ok   random: 12 hex (${first})"; else echo "FAIL random: ${first}"; FAILED=1; fi
check "random: kept" "$(cat "${KEPT}")" "${first}"
check "random: reused" "$(id)" "${first}"
# A good OTP later wins over the kept one.
printf "${R36S}" >"${OTP}"
check "otp wins over the kept id" "$(id)" "e119e1afb0fc"
rm -f "${OTP}"
check "kept id still there" "$(id)" "${first}"
# A broken kept file is made again.
echo junk >"${KEPT}"
again=$(id)
if [[ "${again}" =~ ^[0-9a-f]{12}$ ]] && [ "$(cat "${KEPT}")" = "${again}" ]; then echo "ok   broken kept id replaced"; else echo "FAIL broken kept id: ${again}"; FAILED=1; fi

# Nowhere to keep it: no id, exit 1 (never one that changes every run).
R2="${TMP}/ro"
mkdir -p "${R2}/storage"
chmod 500 "${R2}/storage"
out=$(ARCHR_CONSOLE_ID_ROOT="${R2}" bash "${SCRIPT}" 2>/dev/null)
check "nowhere to keep a random id: exit 1" "$?:${out}" "1:"
chmod 700 "${R2}/storage"

exit ${FAILED}
