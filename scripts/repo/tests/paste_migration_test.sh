#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the move of /usr/bin/paste from busybox to coreutils, with
# the real pacman in a fake root. busybox-1 links paste to pastebinit and
# coreutils-1 also owns it, as on devices today; busybox-2 drops it and
# needs coreutils-2, which ships paste, a spare copy and the real
# 80-archr-paste.hook. Every order and combination, in one transaction or
# several, and a fresh image, must end with GNU paste owned by coreutils.
# The hook never writes through a link: not when paste links to a
# directory, not when a link waits at a temporary name.
# NOHOOK=1 builds coreutils-2 without the hook, to see the test fail.
# Runs unprivileged: unshare -r gives pacman the root it wants and lets
# the hook chroot; inside the root, sh is a host busybox and the other
# tools are the host's GNU coreutils, as on the device.
#   bash scripts/repo/tests/paste_migration_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$(cd "${HERE}/../../.." && pwd)/projects/ArchR/packages/tools/coreutils/hooks/80-archr-paste.hook"
BUSYBOX=${BUSYBOX:-$(command -v busybox || echo /usr/lib/initcpio/busybox)}
for tool in pacman repo-add unshare ldd; do
    command -v "${tool}" >/dev/null || { echo "SKIP: ${tool} not installed"; exit 0; }
done
[ -x "${BUSYBOX}" ] || { echo "SKIP: no busybox (BUSYBOX=/path/to/busybox)"; exit 0; }
unshare -r true 2>/dev/null || { echo "SKIP: user namespaces not available"; exit 0; }

TMP=$(mktemp -d)
trap '[ -n "${KEEPTMP:-}" ] || rm -rf "${TMP}"' EXIT
FAILED=0
GNU='GNU paste'

# --- packages ----------------------------------------------------------------
pkg() { # name rel [depend]
    local p="${TMP}/pkg/$1-$2"
    mkdir -p "${p}/usr/bin"
    printf 'pkgname = %s\npkgbase = %s\npkgver = 1.0-%s\npkgdesc = test\nurl = https://x.invalid\nbuilddate = 1\npackager = test\nsize = 1\narch = any\n' \
        "$1" "$1" "$2" >"${p}/.PKGINFO"
    [ -z "${3:-}" ] || printf 'depend = %s\n' "$3" >>"${p}/.PKGINFO"
    case "$1-$2" in
        busybox-1) printf '#!/bin/sh\n' >"${p}/usr/bin/pastebinit"; ln -s pastebinit "${p}/usr/bin/paste" ;;
        busybox-2) printf '#!/bin/sh\n' >"${p}/usr/bin/pastebinit" ;;
        coreutils-1) echo "${GNU}" >"${p}/usr/bin/paste" ;;
        coreutils-2)
            echo "${GNU}" >"${p}/usr/bin/paste"
            mkdir -p "${p}/usr/lib/coreutils"
            echo "${GNU}" >"${p}/usr/lib/coreutils/paste"
            if [ -z "${NOHOOK:-}" ]; then
                mkdir -p "${p}/etc/pacman.d/hooks"
                cp "${HOOK}" "${p}/etc/pacman.d/hooks/"
            fi
            ;;
    esac
    (cd "${p}" && tar -czf "${TMP}/repo/$1-$2.pkg.tar.gz" .PKGINFO -- *)
}
mkdir -p "${TMP}/repo"
pkg busybox 1
pkg coreutils 1
pkg busybox 2 'coreutils>=1.0-2'
pkg coreutils 2
repo-add -q "${TMP}/repo/test.db.tar.gz" "${TMP}/repo/busybox-2.pkg.tar.gz" \
    "${TMP}/repo/coreutils-2.pkg.tar.gz" 2>/dev/null
printf '[options]\nSigLevel = Never\n[test]\nServer = file://%s\n' "${TMP}/repo" >"${TMP}/pacman.conf"
BB1="${TMP}/repo/busybox-1.pkg.tar.gz" CU1="${TMP}/repo/coreutils-1.pkg.tar.gz"
BB2="${TMP}/repo/busybox-2.pkg.tar.gz" CU2="${TMP}/repo/coreutils-2.pkg.tar.gz"

# --- a root ------------------------------------------------------------------
# Tools for the hook, outside the files the packages own: sh from busybox,
# the rest from the host's GNU coreutils, as on the device.
GNUTOOLS="cp mv mktemp cat chmod rm"
newroot() { # name
    R="${TMP}/root-$1"
    mkdir -p "${R}/var/lib/pacman" "${R}/var/cache/pacman/pkg" "${R}/var/log" \
        "${R}/etc/pacman.d/hooks" "${R}/usr/bin" "${R}/usr/lib/testbb"
    local bin lib
    for bin in "${BUSYBOX}" $(for t in ${GNUTOOLS}; do type -P "${t}"; done); do
        cp "${bin}" "${R}/usr/lib/testbb/"
        for lib in $(ldd "${bin}" 2>/dev/null | grep -o '/[^ ]*'); do
            [ -e "${R}${lib}" ] || { mkdir -p "${R}$(dirname "${lib}")" && cp -L "${lib}" "${R}${lib}"; }
        done
    done
    ln -s "../lib/testbb/$(basename "${BUSYBOX}")" "${R}/usr/bin/sh"
    for bin in ${GNUTOOLS}; do ln -s "../lib/testbb/${bin}" "${R}/usr/bin/${bin}"; done
}
pc() { # pacman in root R, as the device: HookDir = /etc/pacman.d/hooks/
    unshare -r pacman --root "${R}" --dbpath "${R}/var/lib/pacman" --config "${TMP}/pacman.conf" \
        --logfile "${R}/var/log/pacman.log" --hookdir "${R}/etc/pacman.d/hooks" \
        --cachedir "${R}/var/cache/pacman/pkg" --noconfirm "$@" >>"${R}/out.log" 2>&1
}
device() { # name: busybox-1 and coreutils-1, paste a link to pastebinit
    newroot "$1"
    pc -U "${CU1}" && pc -U --overwrite usr/bin/paste "${BB1}"
    [ "$(readlink "${R}/usr/bin/paste")" = pastebinit ] || { echo "FAIL $1: setup"; exit 1; }
}
state() {
    local p="${R}/usr/bin/paste" what
    if [ -L "${p}" ]; then what="link:$(readlink "${p}")"
    elif [ -f "${p}" ]; then what="$(cat "${p}")"
    else what=absent; fi
    echo "${what} | $(unshare -r pacman --config "${TMP}/pacman.conf" --root "${R}" --dbpath "${R}/var/lib/pacman" -Qqo "${p}" 2>/dev/null | tr '\n' ' ')| $(unshare -r pacman --config "${TMP}/pacman.conf" --root "${R}" --dbpath "${R}/var/lib/pacman" -Q 2>/dev/null | tr '\n' ' ')"
}
GOOD="${GNU} | coreutils | busybox 1.0-2 coreutils 1.0-2 "
check() { # scenario rc-of-steps
    local got; got="$(state)"
    if [ "$2" = 0 ] && [ "${got}" = "${GOOD}" ]; then echo "ok   $1: ${got}"
    else echo "FAIL $1 (rc $2): got '${got}'"; FAILED=1; fi
}

# --- devices today -----------------------------------------------------------
scenario() { # name pacman-steps...
    local name="$1" rc=0 step; shift
    device "${name}"
    for step in "$@"; do eval "pc ${step}" || rc=$?; done
    check "${name}" "${rc}"
}
scenario syu                       '-Syu'
scenario syu-coreutils-busybox     '-Syu coreutils busybox'
scenario syu-busybox-coreutils     '-Syu busybox coreutils'
scenario U-busybox-coreutils       '-U "${BB2}" "${CU2}"'
scenario U-coreutils-busybox       '-U "${CU2}" "${BB2}"'
scenario S-busybox-only            '-Sy busybox'
scenario U-busybox-only            '-Sy' '-U "${BB2}"'
scenario S-coreutils-then-syu      '-Sy coreutils' '-Syu'
scenario U-coreutils-then-busybox  '-U "${CU2}"' '-U "${BB2}"'
scenario U-busybox-then-coreutils  '-Sy' '-U "${BB2}"' '-U "${CU2}"'
# Forced past the dependency: paste is gone until coreutils-2 arrives.
scenario Udd-busybox-then-coreutils '-Udd "${BB2}"' '-U "${CU2}"'
scenario U-coreutils-then-syu      '-U "${CU2}"' '-Syu'

# coreutils-2 alone, busybox-1 kept: paste is GNU already (both still own
# it, and pacman -Qo names the first).
device S-coreutils-only
pc -Sy coreutils
got="$(state)"
if [ "${got}" = "${GNU} | busybox | busybox 1.0-1 coreutils 1.0-2 " ]; then
    echo "ok   S-coreutils-only: ${got}"
else echo "FAIL S-coreutils-only: got '${got}'"; FAILED=1; fi

# The hook came with coreutils-2 in the same transaction and still ran.
R="${TMP}/root-U-busybox-coreutils"
if grep -q "running '80-archr-paste.hook'" "${R}/var/log/pacman.log"; then
    echo "ok   a hook installed in the transaction runs at PostTransaction"
else echo "FAIL the new hook did not run"; FAILED=1; fi

# --- a fresh image -----------------------------------------------------------
newroot image
pc -U "${BB2}" "${CU2}"
check "image" $?
pc -Syu; check "image, -Syu" $?
pc -Sy busybox; check "image, reinstall busybox" $?
pc -Sy coreutils; check "image, reinstall coreutils" $?
pc -Sy busybox coreutils; check "image, reinstall both" $?
if grep -q pastebinit "${R}/var/lib/pacman/local/coreutils-1.0-2/files"; then
    echo "FAIL image db"; FAILED=1
fi

# --- publishing never follows a link ----------------------------------------
# paste is a link to a directory: the new file replaces the link and
# nothing lands in the directory.
newroot link-to-dir
pc -U "${BB2}" "${CU2}"
mkdir "${R}/srv-dir"
ln -sfn /srv-dir "${R}/usr/bin/paste"
pc -Sy busybox; rc=$?
if [ "${rc}" = 0 ] && [ ! -L "${R}/usr/bin/paste" ] && [ "$(cat "${R}/usr/bin/paste")" = "${GNU}" ] &&
   [ "$(stat -c %a "${R}/usr/bin/paste")" = 755 ] && [ -z "$(ls -A "${R}/srv-dir")" ]; then
    echo "ok   paste linked to a directory: the link is replaced"
else
    echo "FAIL paste linked to a directory: $(state); in the directory: $(ls -A "${R}/srv-dir" | tr '\n' ' ')"
    FAILED=1
fi
# Whatever waits at a predictable temporary name is never written through.
newroot planted-temp
pc -U "${BB2}" "${CU2}"
echo victim >"${R}/victim"
rm "${R}/usr/bin/paste"
ln -s /victim "${R}/usr/bin/paste.archr-new"
pc -Sy busybox; rc=$?
if [ "${rc}" = 0 ] && [ "$(cat "${R}/victim")" = victim ] && [ ! -L "${R}/usr/bin/paste" ] &&
   [ "$(cat "${R}/usr/bin/paste")" = "${GNU}" ]; then
    echo "ok   a planted temporary link is not followed"
else
    echo "FAIL a planted temporary link: victim '$(cat "${R}/victim")', $(state)"
    FAILED=1
fi
[ -z "$(ls -A "${R}/usr/bin" | grep '^\.paste\.')" ] ||
    { echo "FAIL a temporary file was left in /usr/bin"; FAILED=1; }

# The copy is unreadable: the hook fails and leaves no temporary file.
newroot copy-missing
pc -U "${BB2}" "${CU2}"
rm "${R}/usr/bin/paste" "${R}/usr/lib/coreutils/paste"
pc -Sy busybox
if [ ! -e "${R}/usr/bin/paste" ] && [ -z "$(ls -A "${R}/usr/bin" | grep '^\.paste\.')" ]; then
    echo "ok   a failed copy leaves no temporary file"
else echo "FAIL a failed copy: $(ls -A "${R}/usr/bin" | tr '\n' ' ')"; FAILED=1; fi

# --- the real package.mk files match the toy ones -----------------------------
TOP="$(cd "${HERE}/../../.." && pwd)/projects/ArchR/packages"
mkv() { awk -F'"' -v k="$2" '$1 == k"=" {print $2; exit}' "${TOP}/$1/package.mk"; }
want="coreutils>=$(mkv tools/coreutils PKG_VERSION)-$(mkv tools/coreutils PKG_REV)"
if [ "$(mkv sysutils/busybox PKG_PACMAN_DEPENDS)" = "${want}" ] &&
   ! grep -q 'ln -sf pastebinit' "${TOP}/sysutils/busybox/package.mk" &&
   grep -q 'src/paste .*usr/lib/coreutils' "${TOP}/tools/coreutils/package.mk" &&
   grep -q '80-archr-paste.hook .*etc/pacman.d/hooks' "${TOP}/tools/coreutils/package.mk"; then
    echo "ok   busybox needs ${want}, which ships the copy and the hook"
else echo "FAIL package.mk wiring (busybox must need ${want})"; FAILED=1; fi

[ "${FAILED}" = 0 ] && echo PASS || { echo FAILED; exit 1; }
