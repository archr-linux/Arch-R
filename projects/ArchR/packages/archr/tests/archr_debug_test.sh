#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-debug: on/off write system.loglevel and the capped
# persistent-journal drop-in, status reads pstore. Fake systemctl and
# journalctl; system.cfg in a temporary directory.
#   bash projects/ArchR/packages/archr/tests/archr_debug_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${HERE}/../sources/scripts/archr-debug"
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
mkdir -p "${TMP}/bin" "${R}/sys/fs/pstore" "${R}/sys/module/pstore/parameters"
echo "system.loglevel=none" >"${TMP}/system.cfg"
cat >"${TMP}/profile" <<EOF
get_setting() { sed -n "s/^system.\${1#system.}=//p" "${TMP}/system.cfg"; }
set_setting() { grep -v "^\${1}=" "${TMP}/system.cfg" >"${TMP}/n"; echo "\${1}=\${2}" >>"${TMP}/n"; mv "${TMP}/n" "${TMP}/system.cfg"; }
EOF
printf '#!/bin/sh\necho "$*" >>"%s/calls"\n' "${TMP}" >"${TMP}/bin/systemctl"
printf '#!/bin/sh\necho "journalctl $*" >>"%s/calls"\n' "${TMP}" >"${TMP}/bin/journalctl"
chmod +x "${TMP}/bin/"*
debug() { PATH="${TMP}/bin:${PATH}" ARCHR_DEBUG_PROFILE="${TMP}/profile" ARCHR_DEBUG_ROOT="${R}" bash "${SCRIPT}" "$@"; }

echo "(null)" >"${R}/sys/module/pstore/parameters/backend"
check "off, no pstore" "$(debug status | tr '\n' ' ')" "DEBUG=0 JOURNAL=volatile PSTORE=none CRASHES=0 "
debug on
check "on: exit" "$?" "0"
check "on: loglevel" "$(cat "${TMP}/system.cfg")" "system.loglevel=verbose"
DROPIN="${R}/storage/.cache/journald.conf.d/50-archr-debug.conf"
check "on: persistent and capped" "$(grep -c -e '^Storage=persistent' -e '^SystemMaxUse=16M' -e '^SystemMaxFileSize=4M' "${DROPIN}")" "3"
check "on: journald restarted and flushed" "$(tr '\n' ' ' <"${TMP}/calls")" "restart systemd-journald journalctl --flush "
echo ramoops >"${R}/sys/module/pstore/parameters/backend"
echo oops >"${R}/sys/fs/pstore/dmesg-ramoops-0"
echo log >"${R}/sys/fs/pstore/console-ramoops-0"
check "status with crashes" "$(debug status | tr '\n' ' ')" "DEBUG=1 JOURNAL=persistent PSTORE=ramoops CRASHES=2 "
debug off
check "off: loglevel" "$(cat "${TMP}/system.cfg")" "system.loglevel=none"
check "off: drop-in gone" "$([ -e "${DROPIN}" ] && echo kept || echo gone)" "gone"
debug bogus 2>/dev/null
check "unknown command" "$?" "2"
exit ${FAILED}
