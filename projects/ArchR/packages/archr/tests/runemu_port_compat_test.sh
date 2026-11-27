#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)

# Host test for the port compatibility mode in runemu.sh
# (port_compat_wanted, port_compat_ready, port_compat_learn) and the parts
# of archr-compat-debian that need no root: listed, the manifest check of
# install. Nothing is mounted or downloaded.
#   bash projects/ArchR/packages/archr/tests/runemu_port_compat_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="${HERE}/../sources/scripts"
RUNEMU="${SCRIPTS}/runemu.sh"
TOOL="${SCRIPTS}/archr-compat-debian"
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
for f in "${RUNEMU}" "${TOOL}"; do
  if bash -n "${f}"; then echo "ok   bash -n ${f##*/}"; else echo "FAIL bash -n ${f##*/}"; FAILED=1; fi
done

# --- archr-compat-debian, as an unprivileged user ----------------------------
export ARCHR_COMPAT_SHARE="${TMP}/share" ARCHR_COMPAT_STATE="${TMP}/state"
mkdir -p "${ARCHR_COMPAT_SHARE}"
printf '# comment\nBully*.sh   # trailing\n  Halo.sh\n' >"${ARCHR_COMPAT_SHARE}/ports.list"
"${TOOL}" listed "bully - scholarship.sh"; check "listed: glob, any case" "$?" 0
"${TOOL}" listed "Halo.sh"; check "listed: plain name with spaces around" "$?" 0
"${TOOL}" listed "Other.sh"; check "listed: not on the list" "$?" 1

printf 'runtime image\n' >"${TMP}/img"
sha=$(sha256sum "${TMP}/img" | cut -d' ' -f1)
size=$(stat -c %s "${TMP}/img")
cat >"${ARCHR_COMPAT_SHARE}/manifest" <<EOF
VERSION=1
FILE=rt.squashfs
URL=http://127.0.0.1:9/rt.squashfs
SHA256=${sha}
SIZE=${size}
EOF
"${TOOL}" install "${TMP}/img" 2>/dev/null
check "install: a file that matches the manifest" "$?" 0
check "install: kept under its manifest name" "$(ls "${ARCHR_COMPAT_STATE}" | tr '\n' ' ')" "rt.squashfs rt.squashfs.sha256 "
mkdir -p "${ARCHR_COMPAT_STATE}/upper-0123456789ab" "${ARCHR_COMPAT_STATE}/upper-${sha:0:12}"
: >"${ARCHR_COMPAT_STATE}/old.squashfs"
printf 'other\n' >"${TMP}/bad"
sed -i "s/^SIZE=.*/SIZE=$(stat -c %s "${TMP}/bad")/" "${ARCHR_COMPAT_SHARE}/manifest"
sed -i "s/^FILE=.*/FILE=rt2.squashfs/" "${ARCHR_COMPAT_SHARE}/manifest"
"${TOOL}" install "${TMP}/bad" 2>/dev/null
check "install: a file with another SHA256 is refused" "$?" 1
check "install: and not kept" "$(ls "${ARCHR_COMPAT_STATE}" | grep -c rt2)" 0
# Back to the good image: the other images and layers go.
sed -i "s/^SIZE=.*/SIZE=${size}/; s/^FILE=.*/FILE=rt.squashfs/" "${ARCHR_COMPAT_SHARE}/manifest"
rm -f "${ARCHR_COMPAT_STATE}/rt.squashfs"
"${TOOL}" install "${TMP}/img" 2>/dev/null
check "install: one image and its layer stay" "$(ls "${ARCHR_COMPAT_STATE}" | tr '\n' ' ')" "rt.squashfs rt.squashfs.sha256 upper-${sha:0:12} "
AMIONLINE=false "${TOOL}" ensure; check "ensure: installed and intact" "$?" 0
printf 'other image\n' >"${ARCHR_COMPAT_STATE}/rt.squashfs"
AMIONLINE=false "${TOOL}" ensure; check "ensure: an image of another size is not taken" "$?" 2
rm -f "${ARCHR_COMPAT_STATE}/rt.squashfs"
AMIONLINE=false "${TOOL}" ensure; check "ensure: missing and offline" "$?" 2

# --- runemu.sh --------------------------------------------------------------
eval "$(sed -n '/^function port_dir() {/,/^}/p; /^function port_title() {/,/^}/p;
  /^function prep_run() {/,/^}/p; /^function prep_end() {/,/^}/p;
  /^function port_compat_wanted() {/,/^}/p; /^function port_compat_toast() {/,/^}/p;
  /^function port_compat_ready() {/,/^}/p; /^function port_compat_learn() {/,/^}/p;
  /^COMPAT_SIGNS=/p' "${RUNEMU}")"
log() { :; }
declare -A SETTINGS=()
get_setting() {
  case "$1" in
    system.language) echo "${SETTINGS[lang]:-}" ;;
    compat) echo "${SETTINGS["$3"]:-${SETTINGS[global]:-}}" ;;
  esac
}
COMPAT_STATE="${TMP}/cstate"
COMPAT_SHARE="${ARCHR_COMPAT_SHARE}"
COMPAT="${TOOL}"
OUTPUT_LOG="${TMP}/exec.log"
export ARCHR_TOAST_DIR="${TMP}/notify"
PATH="${SCRIPTS}:${PATH}"
PORTS="${TMP}/ports"
mkdir -p "${PORTS}"
printf '#!/bin/bash\n./game\n' >"${PORTS}/Plain.sh"
printf '#!/bin/bash\n$ESUDO apt-get install -y python3-pygame\n' >"${PORTS}/Apt.sh"
printf '#!/bin/bash\necho "use apt-get install to get it"\n' >"${PORTS}/Echo.sh"
printf '#!/bin/bash\n./halo\n' >"${PORTS}/Halo.sh"

wanted() { port_compat_wanted "${PORTS}/$1" && echo yes || echo no; }
check "wanted: a plain port" "$(wanted Plain.sh)" no
check "wanted: a script that installs with apt-get" "$(wanted Apt.sh)" yes
check "wanted: apt-get only in a message is not an install" "$(wanted Echo.sh)" no
check "wanted: on our list" "$(wanted Halo.sh)" yes
SETTINGS[Halo.sh]=native
check "wanted: system.cfg native wins over the list" "$(wanted Halo.sh)" no
SETTINGS[Plain.sh]=debian
check "wanted: system.cfg debian forces it" "$(wanted Plain.sh)" yes
SETTINGS=([global]=off)
check "wanted: ports.compat=off turns it off" "$(wanted Apt.sh)" no
SETTINGS=()

toast() {
  local f out=""
  for f in "${ARCHR_TOAST_DIR}"/*.toast; do
    [ -f "${f}" ] && out+="$(tr '\n' '|' <"${f}")"
  done
  rm -f "${ARCHR_TOAST_DIR}"/*.toast
  echo "${out}"
}

# Learning from a run: the output after RUN_OFFSET decides.
printf 'old run: error while loading shared libraries: libfoo.so.1\n' >"${OUTPUT_LOG}"
offset=$(stat -c %s "${OUTPUT_LOG}")
echo "ok, nothing missing" >>"${OUTPUT_LOG}"
PORT_COMPAT=0
port_compat_learn "${PORTS}/Plain.sh" "${offset}"
check "learn: an earlier run's error is not this one's" "$(ls "${COMPAT_STATE}/wanted" 2>/dev/null)" ""
echo "./game: /lib/libc.so.6: version \`GLIBC_2.41' not found (required by ./game)" >>"${OUTPUT_LOG}"
port_compat_learn "${PORTS}/Plain.sh" "${offset}"
check "learn: GLIBC_2.41 marks the port" "$(ls "${COMPAT_STATE}/wanted")" "Plain.sh"
check "learn: and says so" "$(toast)" "info|errors|Plain|Next time it opens with Debian's libraries|"
check "wanted: after the mark" "$(wanted Plain.sh)" yes
PORT_COMPAT=1
port_compat_learn "${PORTS}/Plain.sh" "${offset}"
check "learn: failing in compatibility too takes the mark back" "$(ls "${COMPAT_STATE}/wanted")" ""
check "wanted: and never again" "$(wanted Plain.sh)" no
PORT_COMPAT=0
SETTINGS[Apt.sh]=native
port_compat_learn "${PORTS}/Apt.sh" "${offset}"
check "learn: an explicit setting is left alone" "$(ls "${COMPAT_STATE}/wanted")" ""
SETTINGS=()

# Ready: the runtime is there, or offline the port does not start.
AMIONLINE=false
SETTINGS[lang]=pt_BR
port_compat_ready "${PORTS}/Apt.sh"
check "ready: offline and missing" "$?" 1
check "ready: toast in the system language" "$(toast | cut -d'|' -f1-4)" "error|network|Apt|Precisa baixar o Debian: conecte à internet (1 MB)"
cp "${TMP}/img" "${ARCHR_COMPAT_STATE}/rt.squashfs"
echo "${sha}" >"${ARCHR_COMPAT_STATE}/rt.squashfs.sha256"
port_compat_ready "${PORTS}/Apt.sh"
check "ready: installed" "$?" 0

exit "${FAILED}"
