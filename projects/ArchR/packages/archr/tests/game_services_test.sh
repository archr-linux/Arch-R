#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-game-services (Settings › System › During a game) and
# archr-memory-guard: what stops for a game comes back after it, only what
# was running; the guard closes the game's scope only after the pressure
# held, never runemu or itself.
#   bash projects/ArchR/packages/archr/tests/game_services_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="${HERE}/../sources/scripts"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "${TMP}"' EXIT
FAILED=0
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else
    echo "FAIL $1"; echo "     got:      $2"; echo "     expected: $3"; FAILED=1; fi
}

# Settings: one "key=value" per line in ${TMP}/cfg.
cat >"${TMP}/profile" <<'EOF'
get_setting() { sed -n "s/^$1=//p" "${CFG}"; }
EOF
# Units "running" are files in ${TMP}/up; calls are logged.
cat >"${TMP}/systemctl" <<'EOF'
#!/bin/sh
case "$1" in
  is-active) [ -e "${UP}/$3" ] ;;
  stop) shift; for u; do rm -f "${UP}/$u"; done; echo "stop $*" >>"${LOG}" ;;
  start) shift; for u; do touch "${UP}/$u"; done; echo "start $*" >>"${LOG}" ;;
esac
EOF
cat >"${TMP}/wifictl" <<'EOF'
#!/bin/sh
echo "wifi $1" >>"${LOG}"
EOF
cat >"${TMP}/rfkill" <<'EOF'
#!/bin/sh
echo "0: phy0: Wireless LAN"; echo "	Soft blocked: ${BLOCKED:-no}"
EOF
chmod +x "${TMP}/systemctl" "${TMP}/wifictl" "${TMP}/rfkill"
export ARCHR_PROFILE="${TMP}/profile" CFG="${TMP}/cfg" UP="${TMP}/up" LOG="${TMP}/log"
export ARCHR_GAME_SERVICES_STATE="${TMP}/state" ARCHR_SYSTEMCTL="${TMP}/systemctl"
export ARCHR_WIFICTL="${TMP}/wifictl" ARCHR_RFKILL="${TMP}/rfkill"

reset() {
  rm -rf "${UP}" "${LOG}" "${ARCHR_GAME_SERVICES_STATE}"; mkdir -p "${UP}"; : >"${LOG}"
  for u in "$@"; do touch "${UP}/$u"; done
}
svc() { bash "${SCRIPTS}/archr-game-services" "$@"; }
up() { ls "${UP}" | tr '\n' ' '; }

# Defaults: only the sharing pauses.
printf 'wifi.enabled=1\n' >"${CFG}"
reset smbd.service nmbd.service bluetooth.service sshd.service avahi-daemon.socket avahi-daemon.service
svc pause
check "default: sharing stops, the rest stays" "$(up)" "bluetooth.service sshd.service "
check "default: Wi-Fi untouched" "$(grep -c wifi "${LOG}")" 0
svc resume
check "resume brings back what stopped" "$(up)" \
  "avahi-daemon.service avahi-daemon.socket bluetooth.service nmbd.service smbd.service sshd.service "
check "resume leaves no state" "$([ -e "${ARCHR_GAME_SERVICES_STATE}" ] && echo left || echo gone)" gone

# Everything off; a service already down stays down.
printf 'wifi.enabled=1\ngame.wifi=off\ngame.bluetooth=off\ngame.ssh=off\ngame.sharing=pause\n' >"${CFG}"
reset smbd.service bluetooth.service sshd.service
svc pause
check "all off: nothing left running" "$(up)" ""
check "all off: Wi-Fi disabled" "$(grep wifi "${LOG}")" "wifi disable"
svc pause
check "a second pause changes nothing" "$(grep -c '^stop' "${LOG}")" 1
svc resume
check "resume: Wi-Fi back and only those units" "$(up)|$(grep wifi "${LOG}" | tail -1)" \
  "bluetooth.service smbd.service sshd.service |wifi enable"
check "resume twice is harmless" "$(svc resume; echo $?)" 0

# Wi-Fi the player had off is not turned on after the game.
printf 'wifi.enabled=0\ngame.wifi=off\n' >"${CFG}"
reset
svc pause; svc resume
check "Wi-Fi off before: never touched" "$(grep -c wifi "${LOG}")" 0
printf 'wifi.enabled=1\ngame.wifi=off\n' >"${CFG}"
reset
BLOCKED=yes svc pause; svc resume
check "radio blocked before: never touched" "$(grep -c wifi "${LOG}")" 0

# Sharing kept.
printf 'game.sharing=keep\n' >"${CFG}"
reset smbd.service
svc pause
check "sharing kept" "$(up)" "smbd.service "
svc resume

### archr-memory-guard
GUARD="${SCRIPTS}/archr-memory-guard"
psi() { printf 'some avg10=%s avg60=0.00 avg300=0.00 total=1\nfull avg10=%s avg60=0.00 avg300=0.00 total=1\n' "$1" "$1" >"${TMP}/psi"; }
export ARCHR_PSI="${TMP}/psi" ARCHR_GUARD_TICK=0.1 ARCHR_GUARD_HOLD=3 ARCHR_GUARD_LIMIT=40
export ARCHR_KMSG="${TMP}/kmsg" ARCHR_GUARD_NOTE="${TMP}/note" ARCHR_GUARD_PROCS="${TMP}/procs"
start_game() {
  rm -f "${TMP}/kmsg" "${TMP}/note"
  sleep 30 & RUNEMU=$!
  sleep 30 & GAME=$!
  printf '%s\n%s\n' "${RUNEMU}" "${GAME}" >"${TMP}/procs"
}

start_game; psi 12.50
bash "${GUARD}" "${RUNEMU}" "Asphalt" & G=$!
sleep 1
check "low pressure: the game runs" "$(kill -0 "${GAME}" 2>/dev/null && echo running)" running
psi 55.10; sleep 0.15; psi 10.00; sleep 1
check "a short spike is not a stall" "$(kill -0 "${GAME}" 2>/dev/null && echo running)" running
psi 71.00; sleep 1.5
check "held pressure: the game is closed" "$(kill -0 "${GAME}" 2>/dev/null && echo running || echo closed)" closed
check "runemu is left to clean up" "$(kill -0 "${RUNEMU}" 2>/dev/null && echo running)" running
check "the kernel log says out of memory" "$(grep -c 'out of memory' "${TMP}/kmsg" 2>/dev/null)" 1
check "the launcher's note names the game" "$(cat "${TMP}/note" 2>/dev/null)" Asphalt
wait "${G}"; check "the guard ends after closing" "$?" 0
kill "${RUNEMU}" 2>/dev/null

start_game; psi 0.00
bash "${GUARD}" "${RUNEMU}" x & G=$!
sleep 0.3; kill "${RUNEMU}"; sleep 0.5
check "the guard ends with runemu" "$(kill -0 "${G}" 2>/dev/null && echo running || echo ended)" ended
kill "${GAME}" 2>/dev/null

exit "${FAILED}"
