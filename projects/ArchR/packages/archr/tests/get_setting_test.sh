#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for get_setting: keys compare literally, so ROM names with
# [ ] ( ) + . * or / find their own line, and the scopes keep their order
# (game, system, system., plain, global).
#   bash projects/ArchR/packages/archr/tests/get_setting_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

. "${PKG}/profile.d/001-functions" 2>/dev/null
J_CONF="${TMP}/system.cfg"

check() {
  local got
  got=$(get_setting "${@:2}")
  if [ "${got}" != "${1}" ]; then
    echo "FAIL: get_setting ${*:2} -> '${got}', expected '${1}'"
    FAILED=1
  fi
}

cat >"${J_CONF}" <<'CFG'
nes["Gamx [!] (USA).nes"].archr.mangohud.enabled=0
nes["Game [!] (USA).nes"].archr.mangohud.enabled=1
nes["A+B.c*d/e.nes"].core=nestopia
nes["Empty.nes"].core=
nesXcore=regex-dot
nes.core=fceumm
nes.archr.mangohud.enabled=0
snes.cores=
system.cores=4
cores=2
global.threads=3
global.url=http://x/?a=b
archr.mangohud.enabledX=1
CFG

check 1 archr.mangohud.enabled nes "Game [!] (USA).nes"
check 0 archr.mangohud.enabled nes "Other.nes"
check nestopia core nes "A+B.c*d/e.nes"
# An empty game value falls through to the system's.
check fceumm core nes "Empty.nes"
# A dot in the key is a dot, not "any character".
check "" core nesX
check fceumm core nes
check 4 cores snes "Game.sfc"
check 4 cores
check 3 threads nes "Game.nes"
check "http://x/?a=b" url
check "" archr.mangohud.enabled

[ "${FAILED}" = 0 ] && echo "get_setting: ok"
exit "${FAILED}"
