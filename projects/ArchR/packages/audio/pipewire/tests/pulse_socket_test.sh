#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# pipewire-pulse.socket must listen on the exact path pipewire-pulse binds,
# or the server ignores the passed socket and binds its own, leaving the
# unit's socket open with nobody answering (clients falling back to it hang
# for libpulse's 30 s timeout).
#
# What the units decide, checked statically:
#   - the server path: pipewire-pulse builds it from PULSE_RUNTIME_PATH, or
#     XDG_RUNTIME_DIR + "/pulse", plus "/native" (its default unix:native
#     address), and adopts a passed socket only on an exact string match
#     (sd_is_socket_unix compares the bytes);
#   - the socket path: ListenStream= with %t expanded as a system unit does
#     (/run) and /var/run rewritten to /run as systemd does (patch_var_run).
#   bash projects/ArchR/packages/audio/pipewire/tests/pulse_socket_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
UNITS="$(dirname "${HERE}")/system.d"
SOCKET="${UNITS}/pipewire-pulse.socket"
SERVICE="${UNITS}/pipewire-pulse.service"
FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

# The last assignment wins, as in systemd; an empty one resets.
setting() { sed -n "s/^${2}=//p" "${1}" | tail -n1; }
env_of() { sed -n "s/^Environment=\(.*\)$/\1/p" "${SERVICE}" | tr ' ' '\n' | sed -n "s/^${1}=//p" | tail -n1; }

listen=$(setting "${SOCKET}" ListenStream)
[ "$(grep -c '^ListenStream=' "${SOCKET}")" = 1 ] || fail "the socket should listen on one path"
listen=${listen//%t//run}
case "${listen}" in /var/run/*) listen="/run/${listen#/var/run/}" ;; esac

pulse_runtime=$(env_of PULSE_RUNTIME_PATH)
if [ -n "${pulse_runtime}" ]; then
  server="${pulse_runtime}/native"
else
  xdg=$(env_of XDG_RUNTIME_DIR)
  [ -n "${xdg}" ] || fail "pipewire-pulse.service sets no XDG_RUNTIME_DIR"
  server="${xdg//%t//run}/pulse/native"
fi

[ "${listen}" = "${server}" ] ||
  fail "socket listens on '${listen}', pipewire-pulse binds '${server}': the passed socket is never adopted"
case "${listen}" in /run/pulse/*) fail "listening on the system pulse path ${listen}" ;; esac

# The service is the socket's (same name, no Sockets= elsewhere) and needs it.
grep -q '^Requires=.*pipewire-pulse.socket' "${SERVICE}" || fail "the service does not require its socket"
grep -q '^Sockets=' "${SERVICE}" && fail "Sockets= would hand the service other sockets"

# The directory the server makes before start is the one it listens in.
pre=$(setting "${SERVICE}" ExecStartPre)
case "${pre}" in *"mkdir -p ${server%/native}") ;; *) fail "ExecStartPre makes '${pre##* }', the server uses '${server%/native}'" ;; esac

if command -v systemd-analyze >/dev/null; then
  out=$(systemd-analyze verify --man=no "${SOCKET}" "${SERVICE}" 2>&1 |
    grep -v -e 'Command /usr/bin/pipewire-pulse is not executable' -e 'Unit pipewire.service not found' \
      -e 'Unit wireplumber.service not found' -e 'is not executable: No such file')
  [ -z "${out}" ] || fail "systemd-analyze verify: ${out}"
fi

[ ${FAILED} -eq 0 ] && echo "pulse_socket_test: OK (${listen})"
exit ${FAILED}
