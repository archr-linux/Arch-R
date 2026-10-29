#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-emulator-renames: a core saved under an old standalone
# name moves to its -arch name, system-wide and per game; other systems,
# other cores and the emulator key stay; a second run changes nothing.
#   bash projects/ArchR/packages/archr/tests/emulator_renames_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/archr-emulator-renames"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
export ARCHR_SYSTEM_CFG="${TMP}/system.cfg"

cat >"${ARCHR_SYSTEM_CFG}" <<'EOF'
n64.emulator=mupen64plus
n64.core=mupen64plus-sa
n64["Super Mario 64 (USA).z64"].core=mupen64plus-sa
n64["Mario Kart 64.z64"].core=mupen64plus_next
n64.video_plugin=gliden64
n64.core_note=mupen64plus-sa
snes.core=mupen64plus-sa
n64.core=mupen64plus-sa-old
EOF
cat >"${TMP}/want" <<'EOF'
n64.emulator=mupen64plus
n64.core=mupen64plus-arch
n64["Super Mario 64 (USA).z64"].core=mupen64plus-arch
n64["Mario Kart 64.z64"].core=mupen64plus_next
n64.video_plugin=gliden64
n64.core_note=mupen64plus-sa
snes.core=mupen64plus-sa
n64.core=mupen64plus-sa-old
EOF

check() {
  if diff -u "${TMP}/want" "${ARCHR_SYSTEM_CFG}"; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    FAILED=1
  fi
}

bash "${SCRIPT}"
check "old core names move to -arch"
bash "${SCRIPT}"
check "a second run changes nothing"

rm -f "${ARCHR_SYSTEM_CFG}"
if bash "${SCRIPT}" && [ ! -e "${ARCHR_SYSTEM_CFG}" ]; then
  echo "ok: no system.cfg, nothing to do"
else
  echo "FAIL: missing system.cfg"
  FAILED=1
fi

exit "${FAILED}"
