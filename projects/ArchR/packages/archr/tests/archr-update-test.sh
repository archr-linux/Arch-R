#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-update's machine interface (check --json, update
# --progress): the real script against a fake pacman, ping, curl and df on
# PATH, with every path moved into a temporary directory. Never runs pacman.
#   bash projects/ArchR/packages/archr/tests/archr-update-test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${HERE}/../sources/scripts/archr-update"
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

bash -n "${SCRIPT}" && echo "ok   bash -n" || { echo "FAIL bash -n"; FAILED=1; }

mkdir -p "${TMP}/bin" "${TMP}/db/local/x-1" "${TMP}/cache" "${TMP}/power/battery" "${TMP}/run"
echo 1 >"${TMP}/db/local/x-1/desc"
printf 'VERSION="2.1.1"\nBUILD_ID="abc"\n' >"${TMP}/os-release"
echo "updates.branch=next" >"${TMP}/system.cfg"
cat >"${TMP}/profile" <<EOF
get_setting() { sed -n "s/^\${1}=//p" "${TMP}/system.cfg"; }
EOF

# Installed packages and what the repo offers ("name version size").
printf 'linux 6.12.94-3\nretroarch 1.21.0-3\nmesa 26.2.1-1\n' >"${TMP}/installed"
printf 'linux 6.12.95-1 3000\nretroarch 1.22.0-1 2000\nlibnew 1.0-1 1000\n' >"${TMP}/offered"

cat >"${TMP}/bin/pacman" <<'EOF'
#!/bin/bash
# Fake pacman: just enough of -Q, -Sy, -Sup, -Suw and -Su for archr-update.
echo "pacman $*" >>"${FAKE}/calls"
case "$1" in
  -Q) cat "${FAKE}/installed" ;;
  -Sy)
    echo ":: Synchronizing package databases..."
    [ -n "${FAKE_SYNC_FAIL:-}" ] && { echo "error: failed to synchronize all databases (unexpected error)"; exit 1; }
    exit 0 ;;
  -Sup)
    while read -r n v s; do
      echo "$n $v $s https://example.invalid/repo-next/$n-$v-aarch64.pkg.tar.zst"
    done <"${FAKE}/offered" ;;
  -Suw)
    trap 'echo "Interrupt signal received"; exit 130' INT
    mkdir -p "${PACMAN_CACHE}/download-XyZ"
    while read -r n v s; do
      f="$n-$v-aarch64.pkg.tar.zst"
      if [ "$n" = "${FAKE_DOWNLOAD_FAIL:-}" ]; then
        echo "error: failed retrieving file '$f' from example.invalid : Could not resolve host"
        exit 1
      fi
      head -c $((s / 2)) /dev/zero >"${PACMAN_CACHE}/download-XyZ/$f.part"
      sleep "${FAKE_STEP:-0.3}"
      head -c "$s" /dev/zero >"${PACMAN_CACHE}/download-XyZ/$f.part"
      mv "${PACMAN_CACHE}/download-XyZ/$f.part" "${PACMAN_CACHE}/$f"
    done <"${FAKE}/offered"
    rmdir "${PACMAN_CACHE}/download-XyZ" ;;
  -Su)
    echo ":: Starting full system upgrade..."
    echo "checking package integrity..."
    [ -n "${FAKE_FULL:-}" ] && { echo "error: Partition / too full: 9 blocks needed, 1 blocks free"; exit 1; }
    while read -r n v s; do
      echo "upgrading $n..."
      [ -n "${FAKE_INSTALL_FAIL:-}" ] && { echo "error: failed to commit transaction (conflicting files)"; exit 1; }
      sleep "${FAKE_STEP:-0.3}"
    done <"${FAKE}/offered"
    echo ":: Running post-transaction hooks..."
    echo "(1/2) Arming ConditionNeedsUpdate..."
    echo "(2/2) Updating module dependencies..."
    touch "${FAKE}/installed-ok" ;;
esac
EOF
printf '#!/bin/sh\nexit ${FAKE_PING:-0}\n' >"${TMP}/bin/ping"
cat >"${TMP}/bin/curl" <<'EOF'
#!/bin/sh
[ -f "${FAKE}/changelog" ] || exit 22
cat "${FAKE}/changelog"
EOF
cat >"${TMP}/bin/df" <<'EOF'
#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "/dev/root 1000000 1 ${FAKE_FREE_KB:-900000} 1% /"
EOF
# Records its arguments, then runs the holder command it was given.
cat >"${TMP}/bin/systemd-inhibit" <<'EOF'
#!/bin/bash
echo "$*" >"${FAKE}/inhibit"
while [ "${1#--}" != "$1" ]; do shift; done
exec "$@"
EOF
chmod +x "${TMP}/bin/"*
printf '2.1.2\n\nLauncher 1.5: "temas" e sons.\nKernel novo.\n' >"${TMP}/changelog"
echo 80 >"${TMP}/power/battery/capacity"
echo Discharging >"${TMP}/power/battery/status"

run() {
  env PATH="${TMP}/bin:${PATH}" FAKE="${TMP}" ARCHR_UPDATE_PROFILE="${TMP}/profile" \
    MIRRORLIST="${TMP}/mirrorlist" PACMAN_DB="${TMP}/db" PACMAN_CACHE="${TMP}/cache" \
    OS_RELEASE="${TMP}/os-release" UPDATE_LOG="${TMP}/log/archr-update.log" \
    UPDATE_LOCK="${TMP}/run/archr-update.lock" UPDATE_STATE="${TMP}/state" \
    POWER_SUPPLY="${TMP}/power" UPDATE_PROGRESS="${TMP}/run/progress" \
    UPDATE_CANCEL="${TMP}/run/cancel" TICK=0.2 "$@" bash "${SCRIPT}" "${ARGS[@]}"
}
# A field of the last JSON line on stdin.
field() {
  tail -n 1 | python3 -c "import json,sys; v=json.load(sys.stdin).get('$1'); print(json.dumps(v) if isinstance(v,(list,dict,bool)) or v is None else v)"
}
# Wait up to 30 s for a pattern in a file.
wait_for() {
  local n=0
  until grep -q "$1" "$2" 2>/dev/null; do
    sleep 0.1
    n=$((n + 1))
    [ "${n}" -lt 300 ] || return 1
  done
}
reset() {
  rm -rf "${TMP}/cache"/* "${TMP}/state" "${TMP}/calls" "${TMP}/installed-ok" "${TMP}/inhibit"
}

### check --json
ARGS=(check --json)
OUT=$(run)
check "check exits 0" "$?" 0
check "check is one valid JSON line" "$(printf '%s\n' "${OUT}" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin]; print(1)' 2>&1)" 1
check "check os version" "$(field os_version <<<"${OUT}")" 2.1.1
check "check channel" "$(field channel <<<"${OUT}")" next
check "check total" "$(field total <<<"${OUT}")" 3
check "check download size" "$(field download_size <<<"${OUT}")" 6000
check "check kernel needs a reboot" "$(field reboot_reason <<<"${OUT}")" kernel
check "check new version" "$(field new_version <<<"${OUT}")" 2.1.2
check "check news keeps quotes and lines" "$(field news <<<"${OUT}")" 'Launcher 1.5: "temas" e sons.
Kernel novo.'
check "check packages" "$(field packages <<<"${OUT}")" \
  '[{"name": "linux", "old": "6.12.94-3", "new": "6.12.95-1", "size": 3000}, {"name": "retroarch", "old": "1.21.0-3", "new": "1.22.0-1", "size": 2000}, {"name": "libnew", "old": "", "new": "1.0-1", "size": 1000}]'
check "mirrorlist follows the channel" "$(grep '^Server' "${TMP}/mirrorlist")" \
  "Server = https://github.com/archr-linux/archr-repo/releases/download/repo-next"
check "log written" "$(grep -c 'check: 3 package' "${TMP}/log/archr-update.log")" 1

mv "${TMP}/changelog" "${TMP}/changelog.off"
printf 'archr-launcher 1.4.2-1\n' >"${TMP}/installed"
printf 'archr-launcher 1.5.0-1 500\n' >"${TMP}/offered"
OUT=$(run)
check "no changelog: empty notes" "$(field new_version <<<"${OUT}")$(field news <<<"${OUT}")" ""
check "launcher needs a reboot" "$(field reboot_reason <<<"${OUT}")" launcher
: >"${TMP}/offered"
OUT=$(run)
check "nothing pending: exit 0" "$?" 0
check "nothing pending: total 0, no reboot" "$(field total <<<"${OUT}") $(field reboot_required <<<"${OUT}")" "0 false"
OUT=$(FAKE_PING=1 run)
check "no network: exit 1" "$?" 1
check "no network: reason" "$(field error <<<"${OUT}")" network
OUT=$(FAKE_SYNC_FAIL=1 run)
check "sync failure: reason" "$(field error <<<"${OUT}")" sync
exec 8>>"${TMP}/run/archr-update.lock"
flock -n 8
OUT=$(run)
check "second run: busy" "$(field error <<<"${OUT}")" busy
flock -u 8
mv "${TMP}/changelog.off" "${TMP}/changelog"

### update --progress
printf 'linux 6.12.94-3\nretroarch 1.21.0-3\n' >"${TMP}/installed"
printf 'linux 6.12.95-1 3000\nretroarch 1.22.0-1 2000\n' >"${TMP}/offered"
ARGS=(update --progress)
reset
OUT=$(run)
check "update exits 0" "$?" 0
check "every line is JSON" "$(printf '%s\n' "${OUT}" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin]; print(1)' 2>&1)" 1
PHASES=$(printf '%s\n' "${OUT}" | python3 -c '
import json, sys
seen = []
for line in sys.stdin:
    phase = json.loads(line)["phase"]
    if not seen or seen[-1] != phase:
        seen.append(phase)
print(" ".join(seen))')
check "phases in order" "${PHASES}" "sync download install hooks done"
check "download grows to the total" "$(printf '%s\n' "${OUT}" | python3 -c '
import json, sys
d = [json.loads(l) for l in sys.stdin if "\"download\"" in l]
b = [e["bytes"] for e in d]
print(b == sorted(b), d[-1]["percent"], d[-1]["total"], any(e["package"] for e in d))')" "True 100 5000 True"
check "install counts packages" "$(printf '%s\n' "${OUT}" | grep '"install"' | python3 -c '
import json, sys
print(" ".join("%s:%d/%d" % (e["package"], e["current"], e["count"]) for e in map(json.loads, sys.stdin)))')" \
  "linux:1/2 retroarch:2/2"
check "hooks are reported" "$(printf '%s\n' "${OUT}" | grep -c 'Arming ConditionNeedsUpdate')" 1
check "done reports the reboot and versions" "$(field reboot_reason <<<"${OUT}") $(field old_version <<<"${OUT}") $(field new_version <<<"${OUT}") $(field count <<<"${OUT}")" \
  "kernel 2.1.1 2.1.2 2"
check "new version recorded" "$(cat "${TMP}/state/version")" 2.1.2
check "download and install are separate" "$(grep -o 'pacman -S[a-zA-Z]*' "${TMP}/calls" | tr '\n' ' ')" \
  "pacman -Sy pacman -Sup pacman -Suw pacman -Su "
check "the progress file holds the same lines" "$(cat "${TMP}/run/progress")" "${OUT}"
check "install holds a sleep, shutdown and keys inhibitor" "$(cut -d' ' -f1-2 "${TMP}/inhibit")" \
  "--what=sleep:shutdown:handle-power-key:handle-suspend-key --mode=block"
check "pacman output in the log" "$(grep -c '^upgrading linux...' "${TMP}/log/archr-update.log")" 1

reset
OUT=$(FAKE_DOWNLOAD_FAIL=retroarch run)
check "download failure: exit 1" "$?" 1
check "download failure: reason and pacman line" "$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")|$(field changed <<<"${OUT}")" \
  "download|error: failed retrieving file 'retroarch-1.22.0-1-aarch64.pkg.tar.zst' from example.invalid : Could not resolve host|false"
check "download failure installs nothing" "$(grep -c 'pacman -Su ' "${TMP}/calls")" 0

reset
OUT=$(FAKE_INSTALL_FAIL=1 run)
check "install failure: reason" "$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")|$(field changed <<<"${OUT}")" \
  "install|error: failed to commit transaction (conflicting files)|true"
reset
OUT=$(FAKE_FULL=1 run)
check "install without room: space" "$(field reason <<<"${OUT}")|$(field changed <<<"${OUT}")" "space|false"
reset
OUT=$(FAKE_FREE_KB=10 run)
check "no room to download: space before pacman" "$(field reason <<<"${OUT}") $(grep -c 'pacman -Suw' "${TMP}/calls")" "space 0"
echo 20 >"${TMP}/power/battery/capacity"
reset
OUT=$(run)
check "low battery: refused" "$(field reason <<<"${OUT}")" battery
echo Charging >"${TMP}/power/battery/status"
reset
OUT=$(run)
check "low battery on the charger: allowed" "$(field phase <<<"${OUT}")" done
echo 80 >"${TMP}/power/battery/capacity"
echo Discharging >"${TMP}/power/battery/status"

# SIGTERM while downloading cancels; while installing it is ignored.
reset
run FAKE_STEP=1 >"${TMP}/out" &
RUN=$!
wait_for '"download"' "${TMP}/out"
kill -TERM "$(pgrep -P "${RUN}" -f "${SCRIPT}" || echo "${RUN}")" 2>/dev/null
wait "${RUN}"
check "cancel during the download" "$(field reason <"${TMP}/out")" cancelled
check "cancel installs nothing" "$(grep -c 'pacman -Su ' "${TMP}/calls")" 0
# The launcher cancels with a file: it may not be this script's parent.
reset
run FAKE_STEP=1 >"${TMP}/out" &
RUN=$!
wait_for '"download"' "${TMP}/out"
touch "${TMP}/run/cancel"
wait "${RUN}"
check "cancel file during the download" "$(field reason <"${TMP}/out")" cancelled
check "cancel file removed" "$([ -e "${TMP}/run/cancel" ] && echo left || echo gone)" gone
# A run that finds the lock taken leaves the followed file alone.
echo '{"phase":"install"}' >"${TMP}/run/progress"
flock -n 8
OUT=$(run)
check "busy run: reason" "$(field reason <<<"${OUT}")" busy
check "busy run: progress file untouched" "$(cat "${TMP}/run/progress")" '{"phase":"install"}'
flock -u 8
reset
run FAKE_STEP=0.6 >"${TMP}/out" &
RUN=$!
wait_for '"install"' "${TMP}/out"
for PID in $(pgrep -f "${SCRIPT}"); do kill -TERM "${PID}" 2>/dev/null; done
wait "${RUN}"
check "TERM during the install is ignored" "$(field phase <"${TMP}/out") $([ -e "${TMP}/installed-ok" ] && echo installed)" "done installed"

### archr-fake-suspend refuses to suspend while the lock is held
eval "$(sed -n '/^check_update_running()/,/^}/p' "${HERE}/../sources/scripts/archr-fake-suspend")"
UPDATE_LOCK="${TMP}/run/archr-update.lock"
check "fake-suspend: free lock" "$(check_update_running && echo held || echo free)" free
flock -n 8
check "fake-suspend: held lock" "$(check_update_running && echo held || echo free)" held
flock -u 8

exit ${FAILED}
