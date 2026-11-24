#!/bin/bash
# Host test for archr-port-stop: the exit shortcut closes a port's script
# and everything it started, and leaves the runner (runemu.sh) alone.
#   bash projects/ArchR/packages/archr/tests/port_stop_test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STOP="$(dirname "${HERE}")/sources/scripts/archr-port-stop"
FAILED=0
TMP=$(mktemp -d)
# The runners and everything under them (their sleeps hold no TMP path).
tree() {
  local c
  for c in $(pgrep -P "$1"); do tree "${c}"; done
  echo "$1"
}
cleanup() {
  local r
  for r in ${RUNNERS:-}; do
    # shellcheck disable=SC2046
    kill -KILL $(tree "${r}") 2>/dev/null
  done
  rm -rf "${TMP}"
}
trap cleanup EXIT
check() {
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILED=1; fi
}
export CURRENT_GAME="${TMP}/current-game" TICK=0.05 STOP_WAIT=20

# A port named with spaces, as PortMaster's are; it starts a child that
# ignores TERM (a stuck gptokeyb) and one that does not.
mkdir -p "${TMP}/roms (ports)"
ROM="${TMP}/roms (ports)/My Port.sh"
cat >"${ROM}" <<'PORT'
#!/bin/bash
bash -c 'trap "" TERM; while :; do sleep 0.1; done' &
sleep 300 &
wait
PORT
# The runner: a helper beside the game (the memory guard holds only the
# file's name) and the port's script, as runemu.sh has them.
cat >"${TMP}/runner" <<RUN
#!/bin/bash
bash -c "sleep 300; :" "My Port.sh" &
bash "\${1}"
echo done >"${TMP}/runner-after"
sleep 300
RUN
bash "${TMP}/runner" "${ROM}" &
RUNNER=$!
RUNNERS="${RUNNER}"
sleep 0.5
printf '%s\n%s\nports\nportmaster\n\n' "${ROM}" "${RUNNER}" >"${CURRENT_GAME}"
PORT_PID=$(pgrep -P "${RUNNER}" -f "/My Port.sh$" | head -1)
HELPER=$(pgrep -P "${RUNNER}" -f "^bash -c sleep 300; :" | head -1)
KIDS=$(pgrep -P "${PORT_PID}" | tr '\n' ' ')

bash "${STOP}"
check "exit status with a port" "$?" 0
sleep 0.3
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo gone; }
check "the port's script is gone" "$(alive "${PORT_PID}")" gone
for k in ${KIDS}; do check "child ${k} is gone (TERM or KILL)" "$(alive "${k}")" gone; done
check "the runner goes on" "$(alive "${RUNNER}")" alive
check "the runner reaches its next line" "$(cat "${TMP}/runner-after" 2>/dev/null)" done
check "the helper beside the game stays" "$(alive "${HELPER}")" alive

# No port running: the runner has no child holding the ROM.
bash "${STOP}"
check "nothing to close: exit 1" "$?" 1
rm -f "${CURRENT_GAME}"
bash "${STOP}"
check "no current game: exit 1" "$?" 1

# A child that ignores TERM goes with the KILL after STOP_WAIT, in the
# same call: once the script is gone it could no longer be found.
bash "${TMP}/runner" "${ROM}" &
R2=$!
RUNNERS="${RUNNERS} ${R2}"
sleep 0.5
printf '%s\n%s\nports\n' "${ROM}" "${R2}" >"${CURRENT_GAME}"
P2=$(pgrep -P "${R2}" -f "/My Port.sh$" | head -1)
STUCK=$(pgrep -P "${P2}" -f 'trap' | head -1)
check "the stuck child is there" "$(alive "${STUCK}")" alive
bash "${STOP}" 2>"${TMP}/err"
sleep 0.3
check "it is killed" "$(alive "${STUCK}")" gone
check "and the kill is said" "$(cat "${TMP}/err")" "archr-port-stop: My Port.sh did not close, killing it"

exit "${FAILED}"
