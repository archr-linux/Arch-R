#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# build-image.sh: the signed image of the dArkOS compatibility runtime
# (archr-compat-debian), built on the PC.
#
#   tools/compat-debian/build-image.sh OUTDIR [SNAPSHOT]
#
# SNAPSHOT is a snapshot.debian.org time (20261120T000000Z): the same time
# gives the same packages, and with mksquashfs -repro the same image.
# Without it, today's archive. CACHE keeps the .debs between builds
# (default OUTDIR/cache). Writes into OUTDIR:
#   debian-trixie-arm64-<ver>.squashfs   the runtime
#   debian-trixie-arm64-<ver>.squashfs.sig   gpg detached signature
#   manifest   the lines for projects/ArchR/packages/archr/sources/compat-debian/manifest
# The console trusts the image by the SHA256 in that manifest, which ships
# in the (pacman-signed) archr package; the .sig is for anyone checking by
# hand. Publishing is separate: upload both files to the archr-repo
# release named in URL, then commit the manifest.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=${1:?output directory}
snapshot=${2:-}
key=${ARCHR_SIGN_KEY:-0D6AC52FDF8F1252}
arch=${ARCH_LIST:-arm64}
url_base=${URL_BASE:-https://github.com/archr-linux/archr-repo/releases/download/compat-debian}
mksquashfs=${MKSQUASHFS:-$(ls "${here}"/../../build.*/toolchain/bin/mksquashfs 2>/dev/null | head -1)}
[ -x "${mksquashfs}" ] || mksquashfs=$(command -v mksquashfs) ||
  { echo "no mksquashfs (build the toolchain or set MKSQUASHFS)" >&2; exit 1; }

ver=${snapshot:0:8}
[ -n "${ver}" ] || ver=$(date -u +%Y%m%d)
name="debian-trixie-${arch//,/-}-${ver}"
mkdir -p "${out}"
tree="${out}/${name}.rootfs"
[ ! -e "${tree}" ] || { echo "${tree} exists: remove it first" >&2; exit 1; }

# The Debian archive keyring (debian-archive-keyring 2025.1, trixie) checks
# every InRelease; the packages are checked by their SHA256 in it.
keyring=${DEBIAN_KEYRING:-${here}/debian-archive-keyring.gpg}
args=(--out "${tree}" --arch "${arch}" --cache "${CACHE:-${out}/cache}")
[ -n "${snapshot}" ] && args+=(--snapshot "${snapshot}")
[ -n "${keyring}" ] && args+=(--keyring "${keyring}")
python3 -I "${here}/build-rootfs.py" "${args[@]}"

# dArkOS's /opt/inttools files, the same ones the archr package puts on
# the system (gptokeyb itself is Arch R's, run from /.archr/bin).
archr="${here}/../../projects/ArchR/packages/archr/sources"
install -m644 "${archr}"/darkos/* "${tree}/opt/inttools/"
# Arch R's sudo: root already, it runs the command (sudo -u ark, sudo VAR=x).
install -m755 "${archr}/scripts/sudo" "${tree}/usr/bin/sudo"

# Build time of the runtime, read by archr-compat-debian status.
printf 'VERSION=%s\nSNAPSHOT=%s\n' "${ver}" "${snapshot:-none}" >"${tree}/etc/archr-compat-release"

img="${out}/${name}.squashfs"
"${mksquashfs}" "${tree}" "${img}" -noappend -all-root -no-xattrs \
  -comp zstd -Xcompression-level 19 -b 1M -repro-time "$(date -u -d "${ver}" +%s)" -quiet
sha=$(sha256sum "${img}" | cut -d' ' -f1)
size=$(stat -c %s "${img}")
if [ "${NO_SIGN:-0}" != 1 ]; then
  gpg --batch --yes --local-user "${key}" --detach-sign --output "${img}.sig" "${img}"
fi
cat >"${out}/manifest" <<MANIFEST
VERSION=${ver}
FILE=${name}.squashfs
URL=${url_base}/${name}.squashfs
SHA256=${sha}
SIZE=${size}
MANIFEST
echo "${img}: ${size} bytes, sha256 ${sha}"
