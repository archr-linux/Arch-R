#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for archr-modules-firewall: the rules it asks iptables for, run
# twice (a restart must not add a second jump), and the marker the launcher
# waits for only when every rule went in.
#   bash projects/ArchR/packages/archr/tests/modules_firewall_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$(dirname "${HERE}")/sources/scripts/archr-modules-firewall"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
check() {
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; FAILED=1; fi
}
# A fake iptables: logs each call; -C succeeds once a jump was inserted;
# FAIL_ON makes one kind of call fail.
cat >"${TMP}/fake" <<'FAKE'
#!/bin/sh
name=$(basename "$0")
echo "${name} $*" >>"${LOG}"
case " $* " in *" ${FAIL_ON:-none} "*) exit 1 ;; esac
case "$*" in
  "-w -N "*) [ -e "${STATE}.${name}.chain" ] && exit 1; : >"${STATE}.${name}.chain" ;;
  "-w -C OUTPUT "*) [ -e "${STATE}.${name}.jump" ] || exit 1 ;;
  "-w -I OUTPUT "*) : >"${STATE}.${name}.jump" ;;
esac
FAKE
chmod +x "${TMP}/fake"
ln -s fake "${TMP}/ipt4"
ln -s fake "${TMP}/ipt6"
export LOG="${TMP}/log" STATE="${TMP}/state" ARCHR_IPTABLES="${TMP}/ipt4" \
  ARCHR_IP6TABLES="${TMP}/ipt6" ARCHR_MODULES_FIREWALL_MARKER="${TMP}/run/marker" \
  ARCHR_IF_INET6="${TMP}/if_inet6"
: >"${ARCHR_IF_INET6}"

sh "${SCRIPT}"
check "marker after success" '[ -e "${ARCHR_MODULES_FIREWALL_MARKER}" ]'
check "module uids jump to the chain" \
  'grep -qx "ipt4 -w -I OUTPUT 1 -m owner --uid-owner 60600-61099 -j ARCHR-MODULES" "${LOG}"'
check "local addresses refused" \
  'grep -qx "ipt4 -w -A ARCHR-MODULES -m addrtype --dst-type LOCAL -j REJECT" "${LOG}"'
check "the stub answers DNS" \
  'grep -qx "ipt4 -w -A ARCHR-MODULES -d 127.0.0.53 -p udp --dport 53 -j RETURN" "${LOG}"'
check "the stub rules come before the refusal" \
  '[ "$(grep -n "127.0.0.54 -p tcp" "${LOG}" | cut -d: -f1)" -lt "$(grep -n "ipt4 -w -A ARCHR-MODULES -m addrtype" "${LOG}" | cut -d: -f1)" ]'
check "IPv6 too, without the IPv4 stub" \
  'grep -qx "ipt6 -w -A ARCHR-MODULES -m addrtype --dst-type LOCAL -j REJECT" "${LOG}" && ! grep -q "ipt6.*127.0.0" "${LOG}"'

: >"${LOG}"
sh "${SCRIPT}"
check "a rerun flushes the chain" 'grep -qx "ipt4 -w -F ARCHR-MODULES" "${LOG}"'
check "a rerun adds no second jump" '! grep -q "ipt4 -w -I OUTPUT" "${LOG}"'

rm -f "${STATE}".* "${ARCHR_IF_INET6}"
: >"${LOG}"
sh "${SCRIPT}"
check "no IPv6 in the kernel: IPv4 only" '! grep -q "^ipt6" "${LOG}" && [ -e "${ARCHR_MODULES_FIREWALL_MARKER}" ]'

for fail in "--dst-type" "-I"; do
  rm -f "${STATE}".*
  : >"${ARCHR_IF_INET6}"
  FAIL_ON="${fail}" sh "${SCRIPT}" 2>/dev/null
  check "a failing rule (${fail}) leaves no marker" '[ ! -e "${ARCHR_MODULES_FIREWALL_MARKER}" ]'
done
exit ${FAILED}
