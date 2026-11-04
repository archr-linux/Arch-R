#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for "is it running?" guards under BusyBox. BusyBox `pgrep -x`
# compares the whole argv[0], so a daemon started by full path is never
# found: the launcher runs as /usr/bin/archr-launcher. pidof compares the
# basename. The fakes below behave like BusyBox for the processes listed in
# $T/procs (one argv[0] per line).
#   bash projects/ArchR/packages/archr/tests/busybox_process_guards_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="$(dirname "${HERE}")/sources/scripts"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

BIN="${TMP}/bin"
mkdir -p "${BIN}"
tool() { printf '#!/bin/bash\nT=%s\n%s\n' "${TMP}" "$2" >"${BIN}/$1"; chmod +x "${BIN}/$1"; }
tool pgrep '
[ "$1" = -x ] && { grep -qxF -- "$2" "$T/procs" 2>/dev/null && echo 1; exit $?; }
grep -qF -- "$1" "$T/procs" 2>/dev/null && echo 1'
tool pidof '
while read -r p; do [ "${p##*/}" = "$1" ] && { echo 1; exit 0; }; done <"$T/procs" 2>/dev/null
exit 1'
for t in wlr-randr killall systemctl; do tool "$t" "echo \"$t \$*\" >>\"\$T/calls\""; done

check() {
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', want '$3')"; FAILED=1; fi
}
procs() { printf '%s\n' "$@" >"${TMP}/procs"; rm -f "${TMP}/calls"; }

# handle-hdmi-hotplug: acts only while the launcher is on screen.
sed 's|^\. /etc/profile$|:|' "${SCRIPTS}/handle-hdmi-hotplug" >"${TMP}/hotplug"
hotplug() { PATH="${BIN}:${PATH}" sh "${TMP}/hotplug"; }
procs /usr/bin/archr-launcher; hotplug
check "hotplug: launcher started by full path is seen" \
  "$(grep -c '^wlr-randr' "${TMP}/calls" 2>/dev/null)" 2
procs /usr/lib/iwd; hotplug
check "hotplug: no launcher, nothing touched" "$(cat "${TMP}/calls" 2>/dev/null)" ""

# archr-update's take_lock: a db.lck held by a running pacman stays.
sed -n '/^take_lock() {$/,/^}$/p' "${SCRIPTS}/archr-update" >"${TMP}/take_lock"
grep -q flock "${TMP}/take_lock" || { echo "FAIL: take_lock() not found"; exit 1; }
lock() {
  mkdir -p "${TMP}/db"; touch "${TMP}/db/db.lck"
  PATH="${BIN}:${PATH}" bash -c "
    fail() { echo \"fail \$1\"; exit 1; }; logf() { :; }
    UPDATE_LOCK='${TMP}/run/update.lock' PACMAN_DB='${TMP}/db'
    . '${TMP}/take_lock'; take_lock; echo taken"
}
procs /usr/bin/pacman
check "update: pacman started by full path is busy" "$(lock)" "fail busy"
check "update: its db.lck is kept" "$([ -e "${TMP}/db/db.lck" ] && echo kept)" kept
procs pacman
check "update: pacman from PATH is busy" "$(lock)" "fail busy"
procs /usr/bin/pacman-init
check "update: pacman-init is not pacman" "$(lock)" taken
check "update: a stale db.lck goes" "$([ -e "${TMP}/db/db.lck" ] && echo kept || echo gone)" gone

exit "${FAILED}"
