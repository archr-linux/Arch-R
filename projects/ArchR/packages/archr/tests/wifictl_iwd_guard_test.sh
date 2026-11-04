#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for wifictl's iwctl() guard. iwd runs as /usr/lib/iwd, and
# BusyBox `pgrep -x` compares the whole argv[0], so `pgrep -x iwd` never
# matched: every iwctl call returned 1 without running, wifictl waited out
# its polls and reported a failure while iwd joined from the saved profile.
# The fakes below behave like BusyBox for a daemon started by full path.
#   bash projects/ArchR/packages/archr/tests/wifictl_iwd_guard_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/wifictl"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

BIN="${TMP}/bin"
mkdir -p "${BIN}"
tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${TMP}" "$2" >"${BIN}/$1"; chmod +x "${BIN}/$1"; }
# The one running daemon's argv[0] lives in $T/argv0 (absent: not running).
tool pgrep '
[ -f "$T/argv0" ] || exit 1
[ "$1" = -x ] && { [ "$(cat "$T/argv0")" = "$2" ] && echo 1159 && exit 0; exit 1; }
case "$(cat "$T/argv0")" in *"$1"*) echo 1159; exit 0 ;; esac; exit 1'
tool pidof '
[ -f "$T/argv0" ] || exit 1
[ "$(basename "$(cat "$T/argv0")")" = "$1" ] && echo 1159 && exit 0; exit 1'
tool iwctl 'echo "iwctl $*" >>"$T/calls"; echo "State connected"'

# Only the function under test, without the device checks at the top.
sed -n '/^iwctl() {$/,/^}$/p' "${SCRIPT}" >"${TMP}/guard"
grep -q 'iwctl "\$@"' "${TMP}/guard" || { echo "FAIL: iwctl() not found in wifictl"; exit 1; }

run() { PATH="${BIN}:${PATH}" bash -c ". '${TMP}/guard'; iwctl station wlan0 show"; }
check() {
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', want '$3')"; FAILED=1; fi
}

echo /usr/lib/iwd >"${TMP}/argv0"
out=$(run); rc=$?
check "daemon started by full path is found" "${rc}" 0
check "the call reaches iwctl" "${out}" "State connected"
check "iwctl got the arguments" "$(cat "${TMP}/calls" 2>/dev/null)" "iwctl station wlan0 show"

rm -f "${TMP}/argv0" "${TMP}/calls"
out=$(run); rc=$?
check "stopped daemon fails fast" "${rc}" 1
check "stopped daemon never runs iwctl" "$(cat "${TMP}/calls" 2>/dev/null)" ""

exit "${FAILED}"
