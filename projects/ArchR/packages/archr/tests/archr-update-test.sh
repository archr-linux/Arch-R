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

mkdir -p "${TMP}/bin" "${TMP}/db/local/x-1" "${TMP}/storage-cache" "${TMP}/power/battery" "${TMP}/run"
# As on the device: the cache is a symlink into the storage partition.
ln -s "${TMP}/storage-cache" "${TMP}/cache"
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
# The offline path passes --config: keep a copy, serve from its Server.
CONF=""
for ((i = 1; i < $#; i++)); do
  [ "${!i}" = --config ] && { j=$((i + 1)); CONF="${!j}"; }
done
[ -n "${CONF}" ] && cp "${CONF}" "${FAKE}/conf-used"
case "$1" in
  -Q) cat "${FAKE}/installed" ;;
  -Syy)
    echo ":: Synchronizing package databases..."
    SERVER=$(sed -n 's#^Server = file://##p' "${CONF}")
    [ -f "${SERVER}/archr.db" ] && [ -f "${SERVER}/archr.db.sig" ] ||
      { echo "error: failed retrieving file 'archr.db' from file://${SERVER}"; exit 1; }
    [ -n "${FAKE_SIG_FAIL:-}" ] && {
      echo "error: archr: signature from \"Someone <x@example.invalid>\" is invalid"
      echo "error: failed to synchronize all databases (invalid or corrupted database (PGP signature))"
      exit 1; }
    exit 0 ;;
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
      if [ "$n" = "${FAKE_DOWNLOAD_FAIL:-}" ] ||
         { [ "$n" = "${FAKE_DOWNLOAD_FAIL_ONCE:-}" ] && [ ! -e "${FAKE}/failed-once" ]; }; then
        touch "${FAKE}/failed-once"
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
    CACHE=$([ -n "${CONF}" ] && sed -n 's#^CacheDir = ##p' "${CONF}")
    while read -r n v s; do
      [ -n "${CACHE}" ] && [ ! -f "${CACHE}/$n-$v-aarch64.pkg.tar.zst" ] &&
        { echo "error: failed retrieving file '$n-$v-aarch64.pkg.tar.zst' from file:///x : Couldn't open file"; exit 1; }
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
echo "curl $*" >>"${FAKE}/calls"
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
# tar as it is, slowed down to extract when asked (to cancel meanwhile).
cat >"${TMP}/bin/tar" <<EOF
#!/bin/bash
[ "\$1" = -x ] && [ -n "\${FAKE_TAR_SLOW:-}" ] && sleep "\${FAKE_TAR_SLOW}"
exec $(command -v tar) "\$@"
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
    UPDATE_CANCEL="${TMP}/run/cancel" PACMAN_CONF="${TMP}/pacman.conf" \
    ARCHR_UPDATE_OFFLINE_DIR="${TMP}/card/update" OFFLINE_WORK="${TMP}/storage/.archr-update-offline" \
    TICK=0.2 "$@" bash "${SCRIPT}" "${ARGS[@]}"
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
  rm -rf "${TMP}/cache"/* "${TMP}/state" "${TMP}/calls" "${TMP}/installed-ok" "${TMP}/inhibit" "${TMP}/failed-once"
}

### check --json
ARGS=(check --json)
OUT=$(run)
check "check exits 0" "$?" 0
check "check is one valid JSON line" "$(printf '%s\n' "${OUT}" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin]; print(1)' 2>&1)" 1
check "check os version" "$(field os_version <<<"${OUT}")" 2.1.1
# next has no published repo tag yet: it falls back to stable.
check "check channel" "$(field channel <<<"${OUT}")" stable
check "check total" "$(field total <<<"${OUT}")" 3
check "check download size" "$(field download_size <<<"${OUT}")" 6000
check "check kernel needs a reboot" "$(field reboot_reason <<<"${OUT}")" kernel
check "check new version" "$(field new_version <<<"${OUT}")" 2.1.2
check "check news keeps quotes and lines" "$(field news <<<"${OUT}")" 'Launcher 1.5: "temas" e sons.
Kernel novo.'
check "check packages" "$(field packages <<<"${OUT}")" \
  '[{"name": "linux", "old": "6.12.94-3", "new": "6.12.95-1", "size": 3000}, {"name": "retroarch", "old": "1.21.0-3", "new": "1.22.0-1", "size": 2000}, {"name": "libnew", "old": "", "new": "1.0-1", "size": 1000}]'
check "an unpublished channel reads stable" "$(grep '^Server' "${TMP}/mirrorlist")" \
  "Server = https://github.com/archr-linux/archr-repo/releases/download/repo-stable"
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
check "no network: a refusal, exit 75" "$?" 75
check "no network: reason" "$(field error <<<"${OUT}")" network
OUT=$(FAKE_SYNC_FAIL=1 run)
check "sync failure: a fault, exit 1" "$?" 1
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
check "a successful install empties the cache" "$(find "${TMP}/storage-cache" -name '*.pkg.tar*' | wc -l | tr -d ' ')" 0

reset
OUT=$(FAKE_DOWNLOAD_FAIL=retroarch run)
check "download failure: exit 1" "$?" 1
check "download failure: reason and pacman line" "$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")|$(field changed <<<"${OUT}")" \
  "download|error: failed retrieving file 'retroarch-1.22.0-1-aarch64.pkg.tar.zst' from example.invalid : Could not resolve host|false"
check "download failure installs nothing" "$(grep -c 'pacman -Su ' "${TMP}/calls")" 0
check "an interrupted download stays for the next run" "$(find "${TMP}/storage-cache" -name '*.pkg.tar*' | wc -l | tr -d ' ')" 1
check "download failure: tried three times" "$(grep -c 'pacman -Suw' "${TMP}/calls")" 3

reset
OUT=$(FAKE_DOWNLOAD_FAIL_ONCE=retroarch run)
check "a dropped download is tried again and installs" "$?|$(grep -c 'pacman -Suw' "${TMP}/calls")|$(field phase <<<"$(tail -n 1 <<<"${OUT}")")" "0|2|done"

reset
OUT=$(FAKE_INSTALL_FAIL=1 run)
check "install failure: reason" "$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")|$(field changed <<<"${OUT}")" \
  "install|error: failed to commit transaction (conflicting files)|true"
check "a failed install keeps the cache" "$(find "${TMP}/storage-cache" -name '*.pkg.tar*' | wc -l | tr -d ' ')" 2
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

### Update without network: a bundle on the card
cp "${HERE}/../../sysutils/pacman/config/pacman.conf" "${TMP}/pacman.conf"
mkdir -p "${TMP}/card/update" "${TMP}/storage"
CARD="${TMP}/card/update"
# bundle FILE ID [CHANNEL] [PACKAGE TO LEAVE OUT]: a bundle of the offered packages.
bundle() {
  local stage="${TMP}/stage" n v s
  rm -rf "${stage}"
  mkdir -p "${stage}"
  printf 'id=%s\nchannel=%s\ncreated=2026-11-13T12:00:00Z\n' "$2" "${3:-stable}" >"${stage}/archr-update.txt"
  printf '%s\n\n- Launcher: "temas" novos.\n\n- System: fix.\n20261113.1\n\n- Older fix.\n20261112.6\n\n- Oldest.\n' "$2" >"${stage}/changelog.txt"
  echo db >"${stage}/archr.db"
  echo sig >"${stage}/archr.db.sig"
  while read -r n v s; do
    [ "${n}" = "${4:-}" ] && continue
    head -c $((s * 100)) /dev/zero >"${stage}/${n}-${v}-aarch64.pkg.tar.zst"
  done <"${TMP}/offered"
  (cd "${stage}" && command tar -cf "$1" archr-update.txt changelog.txt archr.db archr.db.sig ./*.pkg.tar.zst --transform 's#^\./##')
}
# Nothing on the card or in the work dir; installed update 20261112.6.
offline_reset() {
  reset
  find "${CARD}" -mindepth 1 -delete
  find "${TMP}/storage" -mindepth 1 -delete
  rm -f "${TMP}/conf-used"
  mkdir -p "${TMP}/state"
  echo 20261112.6 >"${TMP}/state/update-id"
}
count() { ls -A "$1" | wc -l | tr -d ' '; }
printf 'linux 6.12.94-3\nretroarch 1.21.0-3\n' >"${TMP}/installed"
printf 'linux 6.12.95-1 3000\nretroarch 1.22.0-1 2000\n' >"${TMP}/offered"

ARGS=(offline --json)
offline_reset
OUT=$(run)
check "offline scan: nothing on the card" "$?|${OUT}" '0|{"found":false}'
echo junk >"${CARD}/archr-update.tar"
check "offline scan: an unreadable file is not an update" "$(run)" '{"found":false}'
bundle "${CARD}/archr-update.tar" 20261113.4
OUT=$(run)
check "offline scan: found, exit 0" "$?|$(field found <<<"${OUT}")|$(field file <<<"${OUT}")|$(field id <<<"${OUT}")|$(field channel <<<"${OUT}")|$(field newer <<<"${OUT}")|$(field current <<<"${OUT}")" \
  "0|true|${CARD}/archr-update.tar|20261113.4|stable|true|20261112.6"
check "offline scan: changelog down to the installed id" "$(field changelog <<<"${OUT}")" \
  '["- Launcher: \"temas\" novos.", "- System: fix.", "- Older fix."]'
bundle "${CARD}/archr-update-20261113.10.tar" 20261113.10
bundle "${CARD}/archr-update-20261113.9.tar" 20261113.9
check "offline scan: the newest of several" "$(field id <<<"$(run)")" 20261113.10
bundle "${CARD}/archr-update-next.tar" 20261120.1 next
check "offline scan: this console's channel first" "$(field id <<<"$(run)")" 20261113.10
offline_reset
bundle "${CARD}/archr-update.tar" 20261120.1 next
OUT=$(run)
check "offline scan: another channel is reported as such" "$(field found <<<"${OUT}") $(field channel <<<"${OUT}")" "true next"
bundle "${CARD}/archr-update.tar" 20261112.6
OUT=$(run)
check "offline scan: the installed id is not newer" "$(field newer <<<"${OUT}")|$(field changelog <<<"${OUT}")" "false|[]"
bundle "${CARD}/archr-update.tar" 20261111.2
check "offline scan: an older id is not newer" "$(field newer <<<"$(run)")" false
rm -f "${TMP}/state/update-id"
echo 20261113 >"${TMP}/state/version"
check "offline scan: an id recorded as version counts" "$(field current <<<"$(run)")" 20261113
rm -f "${TMP}/state/version"
bundle "${CARD}/archr-update.tar" 20261113.4
OUT=$(run)
check "offline scan: never updated: newer, the first id's notes" "$(field current <<<"${OUT}")|$(field newer <<<"${OUT}")|$(field changelog <<<"${OUT}")" \
  '|true|["- Launcher: \"temas\" novos.", "- System: fix."]'
ARGS=(offline)
check "offline scan: a human line" "$(run)" \
  "${CARD}/archr-update.tar brings update 20261113.4 (installed: none). Install it with: archr-update update --from ${CARD}/archr-update.tar"

# update --from: works with no network, and touches none.
offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4
SIZE=$(stat -c %s "${CARD}/archr-update.tar")
ARGS=(update --from "${CARD}/archr-update.tar" --progress)
OUT=$(FAKE_PING=1 run)
check "update --from exits 0 without network" "$?" 0
check "update --from: every line is JSON" "$(printf '%s\n' "${OUT}" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin]; print(1)' 2>&1)" 1
PHASES=$(printf '%s\n' "${OUT}" | python3 -c '
import json, sys
seen = []
for line in sys.stdin:
    phase = json.loads(line)["phase"]
    if not seen or seen[-1] != phase:
        seen.append(phase)
print(" ".join(seen))')
check "update --from: phases" "${PHASES}" "extract sync install hooks done"
check "update --from: extract reaches 100" "$(grep '"extract"' <<<"${OUT}" | field percent) $(grep '"extract"' <<<"${OUT}" | field total)" "100 ${SIZE}"
check "update --from: done" "$(field count <<<"${OUT}") $(field reboot_reason <<<"${OUT}") $(field new_version <<<"${OUT}")" "2 kernel 20261113.4"
check "update --from: no download, no curl" "$(grep -o '^pacman -S[a-zA-Z]*\|^curl' "${TMP}/calls" | tr '\n' ' ')" \
  "pacman -Syy pacman -Sup pacman -Su "
check "update --from: [archr] served from the work dir" "$(sed -n '/^\[archr\]/,$p' "${TMP}/conf-used" | grep -v '^#' | grep -v '^$')" \
  "[archr]
Server = file://${TMP}/storage/.archr-update-offline"
check "update --from: cache in the work dir, SigLevel untouched" \
  "$(grep -c "^CacheDir = ${TMP}/storage/.archr-update-offline/\$" "${TMP}/conf-used") $(grep -c '^CacheDir' "${TMP}/conf-used") $(grep '^SigLevel' "${TMP}/conf-used")" \
  "1 1 SigLevel    = PackageOptional DatabaseRequired"
check "update --from: the tar is deleted" "$(count "${CARD}")" 0
check "update --from: the work dir is removed" "$(count "${TMP}/storage")" 0
check "update --from: id recorded" "$(cat "${TMP}/state/update-id") $(cat "${TMP}/state/version")" "20261113.4 20261113.4"
check "update --from: the progress file holds the same lines" "$(cat "${TMP}/run/progress")" "${OUT}"
bundle "${CARD}/archr-update.tar" 20261113.4
ARGS=(offline --json)
check "after the update the same file is not newer" "$(run | field newer)" false
ARGS=(update --progress --from "${CARD}/archr-update.tar")
OUT=$(run)
check "update --from an old file: offline-old, exit 75" "$?|$(field reason <<<"${OUT}")|$(field message <<<"${OUT}")" \
  "75|offline-old|This update file (20261113.4) is not newer than the installed update (20261113.4)."
check "an old file stays" "$(ls "${CARD}")" archr-update.tar

offline_reset
echo junk >"${CARD}/archr-update.tar"
ARGS=(update --from "${CARD}/archr-update.tar")
OUT=$(run)
check "invalid tar: offline-invalid, exit 1" "$?|$(field reason <<<"${OUT}")|$(field changed <<<"${OUT}")" "1|offline-invalid|false"
check "invalid tar: pacman not run" "$(cat "${TMP}/calls" 2>/dev/null | grep -c 'pacman -S')" 0
ARGS=(update --from "${TMP}/nowhere.tar")
check "no such file: offline-invalid" "$(run | field reason)" offline-invalid
# A tar with a path in it is refused before anything is extracted.
offline_reset
bundle "${TMP}/b.tar" 20261113.4
mkdir -p "${TMP}/stage2/sub"
echo x >"${TMP}/stage2/sub/evil"
(cd "${TMP}/stage" && command tar -cf "${CARD}/archr-update.tar" archr-update.txt changelog.txt archr.db archr.db.sig -C "${TMP}/stage2" sub/evil)
ARGS=(update --from "${CARD}/archr-update.tar")
check "a tar with a directory: offline-invalid, nothing extracted" "$(run | field reason) $(count "${TMP}/storage")" "offline-invalid 0"
offline_reset
bundle "${CARD}/archr-update.tar" 20261120.1 next
check "another channel: offline-invalid" "$(run | field message)" "This update file is for the next channel; this console is on stable."

offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4
OUT=$(FAKE_SIG_FAIL=1 run)
check "db signature refused: offline-invalid" "$?|$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")" \
  "1|offline-invalid|error: failed to synchronize all databases (invalid or corrupted database (PGP signature))"
check "db signature refused: nothing installed, tar kept, work dir removed" \
  "$(cat "${TMP}/calls" 2>/dev/null | grep -c 'pacman -Su ')|$(ls "${CARD}")|$(count "${TMP}/storage")" "0|archr-update.tar|0"
check "db signature refused: nothing recorded" "$(cat "${TMP}/state/update-id")" 20261112.6

offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4 stable retroarch
OUT=$(run)
check "missing package: offline-incomplete, exit 75" "$?|$(field reason <<<"${OUT}")|$(field line <<<"${OUT}")|$(field changed <<<"${OUT}")" \
  "75|offline-incomplete|missing: retroarch|false"
check "missing package: nothing installed, tar kept" "$(cat "${TMP}/calls" 2>/dev/null | grep -c 'pacman -Su ')|$(ls "${CARD}")" "0|archr-update.tar"

offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4
echo 20 >"${TMP}/power/battery/capacity"
OUT=$(run)
check "update --from, low battery: refused" "$?|$(field reason <<<"${OUT}")|$(count "${TMP}/storage")" "75|battery|0"
echo 80 >"${TMP}/power/battery/capacity"
OUT=$(FAKE_FREE_KB=10 run)
check "update --from, no room to unpack: space before extracting" "$?|$(field reason <<<"${OUT}")|$(grep -c '"extract","bytes":[1-9]' <<<"${OUT}")" "75|space|0"
flock -n 8
mkdir -p "${TMP}/storage/.archr-update-offline"
check "update --from while another runs: busy, its work dir kept" \
  "$(run | field reason) $(ls -A "${TMP}/storage")" "busy .archr-update-offline"
flock -u 8

# Cancel while extracting: by SIGTERM and by the cancel file.
offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4
run FAKE_TAR_SLOW=3 >"${TMP}/out" &
RUN=$!
wait_for '"extract"' "${TMP}/out"
sleep 0.5
kill -TERM "$(pgrep -P "${RUN}" -f "${SCRIPT}" || echo "${RUN}")" 2>/dev/null
wait "${RUN}"
check "cancel during the extract" "$(field reason <"${TMP}/out")" cancelled
check "cancel: nothing synced, tar kept, work dir removed" \
  "$(cat "${TMP}/calls" 2>/dev/null | grep -c 'pacman -S')|$(ls "${CARD}")|$(count "${TMP}/storage")" "0|archr-update.tar|0"
offline_reset
bundle "${CARD}/archr-update.tar" 20261113.4
run FAKE_TAR_SLOW=3 >"${TMP}/out" &
RUN=$!
wait_for '"extract"' "${TMP}/out"
touch "${TMP}/run/cancel"
wait "${RUN}"
check "cancel file during the extract" "$(field reason <"${TMP}/out") $([ -e "${TMP}/run/cancel" ] && echo left || echo gone)" "cancelled gone"
rm -f "${TMP}/state/update-id"

### version: the recorded one only when newer than the image's
ARGS=(version)
rm -rf "${TMP}/state"
check "version: image" "$(run)" 2.1.1
mkdir -p "${TMP}/state"
echo 2.1.10 >"${TMP}/state/version"
check "version: recorded newer" "$(run)" 2.1.10
printf 'VERSION="2.2.0"\nBUILD_ID="abc"\n' >"${TMP}/os-release"
check "version: newer image flashed" "$(run)" 2.2.0

### archr-fake-suspend refuses to suspend while the lock is held
eval "$(sed -n '/^check_update_running()/,/^}/p' "${HERE}/../sources/scripts/archr-fake-suspend")"
UPDATE_LOCK="${TMP}/run/archr-update.lock"
check "fake-suspend: free lock" "$(check_update_running && echo held || echo free)" free
flock -n 8
check "fake-suspend: held lock" "$(check_update_running && echo held || echo free)" held
flock -u 8

exit ${FAILED}
