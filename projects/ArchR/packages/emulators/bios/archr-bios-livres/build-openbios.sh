#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)
#
# Rebuilds files/openbios.bin from source, the way PCSX-Redux builds it:
# the nugget mirror of pcsx-redux/src/mips at the commit pcsx-redux pins,
# compiled in the project's own build image (mipsel-none-elf GCC). Two
# clean builds give the same bytes; the result must match OPENBIOS_SHA256
# in package.mk. Needs docker or podman and network.
#   bash build-openbios.sh [output]
set -eu
COMMIT=db68789861e1205bbd677bb4af5dca19c84433d1
IMAGE=ghcr.io/grumpycoders/pcsx-redux-build:latest
OUT=$(realpath -m "${1:-$(dirname "$0")/files/openbios.bin}")
RUNTIME=$(command -v docker || command -v podman)
# Files written in the mounted tree must stay the caller's.
case "${RUNTIME}" in
  *podman) OWNER=(--userns=keep-id) ;;
  *) OWNER=(--user "$(id -u):$(id -g)") ;;
esac
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
git clone -q --filter=blob:none https://github.com/pcsx-redux/nugget.git "${WORK}/nugget"
git -C "${WORK}/nugget" checkout -q "${COMMIT}"
"${RUNTIME}" run --rm "${OWNER[@]}" --security-opt=label=disable \
  -v "${WORK}/nugget:/project" -w /project/openbios "${IMAGE}" make -j"$(nproc)"
cp "${WORK}/nugget/openbios/openbios.bin" "${OUT}"
sha256sum "${OUT}"
