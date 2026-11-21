#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

# Host test for the ports' systemctl shim: starting, stopping or restarting
# EmulationStation (which ArchR does not have) succeeds without calling the
# real systemctl; every other call reaches it unchanged, with its exit code.
# runemu.sh puts the shim first on a port's PATH.
#   bash projects/ArchR/packages/archr/tests/port_shim_systemctl_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SHIM="${HERE}/../sources/port-shims/systemctl"
RUNEMU="${HERE}/../sources/scripts/runemu.sh"
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
if sh -n "${SHIM}"; then echo "ok   sh -n"; else echo "FAIL sh -n"; FAILED=1; fi

cat >"${TMP}/real" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
exit 5
EOF
chmod +x "${TMP}/real"
export ARCHR_REAL_SYSTEMCTL="${TMP}/real" CALLS="${TMP}/calls"

run() {
  : >"${CALLS}"
  sh "${SHIM}" "$@"
  echo "$?:$(cat "${CALLS}")"
}

check "restart emustation"            "$(run restart emustation)"                  "0:"
check "restart emustation.service"    "$(run restart emustation.service)"          "0:"
check "--no-block restart"            "$(run --no-block restart emulationstation)" "0:"
check "stop emulationstation.service" "$(run stop emulationstation.service)"       "0:"
check "start emustation"              "$(run start emustation)"                    "0:"
check "status passes through"         "$(run status emustation)"                   "5:status emustation"
check "is-active passes through"      "$(run is-active emustation)"                "5:is-active emustation"
check "other unit passes through"     "$(run restart input)"                       "5:restart input"
check "mixed units pass through"      "$(run restart emustation input)"            "5:restart emustation input"
check "no arguments pass through"     "$(run)"                                     "5:"

line=$(grep -n 'export PATH="/usr/lib/archr/port-shims:${PATH}"' "${RUNEMU}" | cut -d: -f1)
ports=$(grep -n '^      "ports")' "${RUNEMU}" | cut -d: -f1)
check "runemu puts the shim on the ports' PATH" \
  "$([ -n "${line}" ] && [ -n "${ports}" ] && [ "${line}" -gt "${ports}" ] && [ $((line - ports)) -lt 8 ] && echo yes)" yes

exit "${FAILED}"
