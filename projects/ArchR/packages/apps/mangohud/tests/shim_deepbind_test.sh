#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for the MangoHud OpenGL shim. ArchR links MangoHud against the
# shared libstdc++ (0001-No-static-lib), so the shim must not dlopen the
# overlay with RTLD_DEEPBIND: in a non-PIE program with copy relocations
# (flycast, ppsspp) the overlay would see other std::locale facet ids and
# std::use_facet would throw std::bad_cast.
#   bash projects/ArchR/packages/apps/mangohud/tests/shim_deepbind_test.sh
# Part 1 needs the MangoHud tarball in sources/ (skipped without it);
# part 2 needs g++ (skipped without it).

# check() evals its quoted condition, so the variables it reads look unused.
# shellcheck disable=SC2016,SC2034
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "${HERE}")
ROOT=$(cd "${PKG}/../../../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

check() {
  if eval "${2}"; then
    echo "ok   ${1}"
  else
    echo "FAIL ${1}"
    FAILED=1
  fi
}

### 1. The patched shim opens the overlay without RTLD_DEEPBIND.
VERSION=$(sed -n 's/^PKG_VERSION="\([0-9a-f]*\)".*/\1/p' "${PKG}/package.mk")
TARBALL="${ROOT}/sources/mangohud/mangohud-${VERSION}.tar.gz"
if [ -f "${TARBALL}" ]; then
  tar xzf "${TARBALL}" -C "${TMP}"
  SRC=$(echo "${TMP}"/MangoHud-*)
  for p in "${PKG}"/patches/*.patch; do
    patch -s -p1 -d "${SRC}" <"${p}" || { echo "FAIL patch $(basename "${p}")"; FAILED=1; }
  done
  SHIM="${SRC}/src/gl/shim.c"
  check "shim dlopens the overlay three times" \
    '[ "$(grep -c "handle = dlopen(.*RTLD_NOW" "${SHIM}")" = 3 ]'
  check "no dlopen in the shim asks for RTLD_DEEPBIND" \
    '! grep "dlopen(" "${SHIM}" | grep -q RTLD_DEEPBIND'
  check "the overlay still binds its own functions (-Bsymbolic-functions)" \
    'grep -q "Bsymbolic-functions" "${SRC}/src/meson.build"'
else
  echo "skip part 1: ${TARBALL} not found"
fi

### 2. Why: a deep-bound library sees another std::ctype<char>::id.
if command -v g++ >/dev/null 2>&1; then
  cat >"${TMP}/lib.cpp" <<'EOF'
#include <locale>
extern "C" const void *facet_id() { return &std::ctype<char>::id; }
EOF
  cat >"${TMP}/main.cpp" <<'EOF'
#include <dlfcn.h>
#include <locale>
#include <cstdio>
#include <cstdlib>
int main(int, char **argv) {
  int flags = RTLD_NOW | RTLD_LOCAL | (atoi(argv[2]) ? RTLD_DEEPBIND : 0);
  void *h = dlopen(argv[1], flags);
  if (!h) return 2;
  auto id = (const void *(*)())dlsym(h, "facet_id");
  return id() == &std::ctype<char>::id ? 0 : 1;
}
EOF
  if g++ -shared -fPIC -Wl,-Bsymbolic-functions "${TMP}/lib.cpp" -o "${TMP}/lib.so" &&
     g++ -fno-pie -no-pie "${TMP}/main.cpp" -o "${TMP}/main" -ldl; then
    check "non-PIE program has a copy relocation of std::ctype<char>::id" \
      'readelf -rW "${TMP}/main" | grep COPY | grep -q _ZNSt5ctypeIcE2idE'
    check "without RTLD_DEEPBIND the overlay shares the program's facet id" \
      '"${TMP}/main" "${TMP}/lib.so" 0'
    "${TMP}/main" "${TMP}/lib.so" 1; DEEP=$?
    check "with RTLD_DEEPBIND the ids differ (the std::bad_cast cause)" '[ "${DEEP}" = 1 ]'
  else
    echo "skip part 2: g++ could not build the probe"
  fi
else
  echo "skip part 2: g++ not found"
fi

exit "${FAILED}"
