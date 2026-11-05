#!/bin/bash
# Host test for pkg-identity's version of git-pinned packages: a package.mk
# with a 40-hex PKG_VERSION becomes 1:0.git<date>.<sha7>, each bump sorts
# higher in vercmp whatever the hash, the new form beats the bare hashes
# devices have installed, and other versions are left alone.
#   bash scripts/repo/tests/pkg_identity_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
IDENTITY="$(dirname "${HERE}")/pkg-identity"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
command -v vercmp >/dev/null || { echo "SKIP: vercmp not installed"; exit 0; }

check() { # name got want
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; FAILED=1; fi
}
newer() { # name a b: vercmp a b must be 1
    check "$1 ($2 > $3)" "$(vercmp "$2" "$3")" 1
}

SHA_A=1018f17a629c638acc1a01df19e3f2146e7b4f5c   # starts with a digit
SHA_B=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678   # sorts below SHA_A as a bare hash
SHA_C=0000000000000000000000000000000000000001   # sorts below both

# A source tree in git: a pinned driver, a package reusing its version,
# and a normal one.
SRC="${TMP}/src"
mkdir -p "${SRC}/packages/drivers/AIC8800" "${SRC}/packages/drivers/AIC8800-extra" \
         "${SRC}/packages/tools/zlib" "${TMP}/install_pkg"
cd "${SRC}" || exit 1
git init -q .
git config user.email t@t
git config user.name t
pkgmk() { printf 'PKG_NAME="%s"\nPKG_VERSION="%s"\nPKG_URL="https://x/%s.tar.gz"\n' "$1" "$2" "$2"; }
commit() { # date message
    git add -A
    GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" git commit -qm "$2"
}
pkgmk AIC8800 "${SHA_A}" >packages/drivers/AIC8800/package.mk
printf 'PKG_NAME="AIC8800-extra"\nPKG_VERSION="$(get_pkg_version AIC8800)"\n' \
    >packages/drivers/AIC8800-extra/package.mk
pkgmk zlib 1.3.1 >packages/tools/zlib/package.mk
commit "2026-11-04T20:45:30Z" "first pin"

identity() { # install_pkg dirname -> "name version fileversion pkgrel"
    mkdir -p "${TMP}/install_pkg/$1"
    (
        . "${IDENTITY}" 2>/dev/null
        name="" version="" fileversion="" pkgrel="" replaces="" pkgmk="" relmk=""
        pkg_identity "${TMP}/install_pkg/$1"
        echo "${name} ${version} ${fileversion} ${pkgrel}"
    )
}

# 1. The generated pkgver; the archive name drops the epoch.
v1="$(identity "AIC8800-${SHA_A}")"
check "pinned pkgver" "${v1}" "AIC8800 1:0.git20261104T2045.1018f17 0.git20261104T2045.1018f17 1"
v1="$(cut -d' ' -f2 <<<"${v1}")"
check "dynamic PKG_VERSION follows its source" "$(identity "AIC8800-extra-${SHA_A}" | cut -d' ' -f2)" "${v1}"
check "normal package unchanged" "$(identity "zlib-1.3.1")" "zlib 1.3.1 1.3.1 1"
check "pkg_git_pkgver" "$(. "${IDENTITY}" && pkg_git_pkgver "${SHA_A}" packages/drivers/AIC8800/package.mk)" "${v1}"

# 2. Two bumps in order, to hashes that sort lower and lower as bare hashes.
check "bare hashes: the bump looks like a downgrade" "$(vercmp "${SHA_B}-1" "${SHA_A}-1")" -1
pkgmk AIC8800 "${SHA_B}" >packages/drivers/AIC8800/package.mk
commit "2026-11-05T09:00:00Z" "bump 1"
v2="$(identity "AIC8800-${SHA_B}" | cut -d' ' -f2)"
check "bump 1 pkgver" "${v2}" "1:0.git20261105T0900.a1b2c3d"
newer "bump 1" "${v2}-1" "${v1}-1"
check "bump 1 dates its dependent" "$(identity "AIC8800-extra-${SHA_B}" | cut -d' ' -f2)" "${v2}"
pkgmk AIC8800 "${SHA_C}" >packages/drivers/AIC8800/package.mk
commit "2026-11-05T21:10:00Z" "bump 2"
v3="$(identity "AIC8800-${SHA_C}" | cut -d' ' -f2)"
newer "bump 2" "${v3}-1" "${v2}-1"
newer "bump 2 over first" "${v3}-1" "${v1}-1"
# Same day, later time; next year with an earlier clock.
newer "same day" "1:0.git20261105T2110.0000000-1" "1:0.git20261105T0900.fffffff-1"
newer "next year" "1:0.git20270101T0000.0000000-1" "1:0.git20261231T2359.fffffff-1"

# 3. Transition: the new form beats any bare hash installed today.
newer "transition (AIC8800)" "1:0.git20261104T2045.1018f17-1" "${SHA_A}-1"
for old in "${SHA_A}" "${SHA_B}" ffffffffffffffffffffffffffffffffffffffff 9999999999999999999999999999999999999999; do
    newer "transition from ${old:0:7}, even the fallback date" "1:0.git00000000T0000.0000000-1" "${old}-2"
done

# 4. A normal package keeps its plain version and ordering.
check "normal versions" "$(vercmp 1.3.1-1 1.3.0-1)" 1
check "normal version not git-dated" "$(identity "zlib-1.3.1" | cut -d' ' -f2)" "1.3.1"

# 5. An uncommitted edit dates from the file's mtime (UTC).
pkgmk AIC8800 "${SHA_A}" >packages/drivers/AIC8800/package.mk
touch -d "2026-11-06T03:04:00Z" packages/drivers/AIC8800/package.mk
check "dirty package.mk" "$(identity "AIC8800-${SHA_A}" | cut -d' ' -f2)" "1:0.git20261106T0304.1018f17"
git checkout -q -- packages

# 6. No git history (source tarball): a fixed date older than any real one.
mkdir -p "${TMP}/tarball"
cp -r "${SRC}/packages" "${TMP}/tarball/"
check "no git fallback" "$(cd "${TMP}/tarball" && GIT_CEILING_DIRECTORIES="${TMP}" bash -c ". '${IDENTITY}' 2>/dev/null; pkg_git_pkgver ${SHA_C} packages/drivers/AIC8800/package.mk")" \
    "1:0.git00000000T0000.0000000"

[ "${FAILED}" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
