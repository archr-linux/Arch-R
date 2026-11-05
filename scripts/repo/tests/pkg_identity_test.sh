#!/bin/bash
# Host test for pkg-identity's version of git-pinned packages: a package.mk
# with a 40-hex PKG_VERSION becomes 1:0.git<YYYYMMDDTHHMMSS>.<sha7>, each
# bump sorts higher in vercmp whatever the hash, the new form beats the bare
# hashes devices have installed, other versions are left alone, the image db
# and the repo of one build agree, and a tree without full git history is
# refused unless ARCHR_PKGVER_ALLOW_NOGIT=1.
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
mkdir -p "${SRC}/projects/ArchR/packages" "${SRC}/projects/ArchR/devices" \
         "${SRC}/packages/drivers/AIC8800" "${SRC}/packages/drivers/AIC8800-extra" \
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
check "pinned pkgver" "${v1}" "AIC8800 1:0.git20261104T204530.1018f17 0.git20261104T204530.1018f17 1"
v1="$(cut -d' ' -f2 <<<"${v1}")"
check "dynamic PKG_VERSION follows its source" "$(identity "AIC8800-extra-${SHA_A}" | cut -d' ' -f2)" "${v1}"
check "normal package unchanged" "$(identity "zlib-1.3.1")" "zlib 1.3.1 1.3.1 1"
check "pkg_git_pkgver" "$(. "${IDENTITY}" && pkg_git_pkgver "${SHA_A}" packages/drivers/AIC8800/package.mk)" "${v1}"

# 2. Two bumps in order, to hashes that sort lower and lower as bare hashes.
check "bare hashes: the bump looks like a downgrade" "$(vercmp "${SHA_B}-1" "${SHA_A}-1")" -1
pkgmk AIC8800 "${SHA_B}" >packages/drivers/AIC8800/package.mk
commit "2026-11-05T09:00:00Z" "bump 1"
v2="$(identity "AIC8800-${SHA_B}" | cut -d' ' -f2)"
check "bump 1 pkgver" "${v2}" "1:0.git20261105T090000.a1b2c3d"
newer "bump 1" "${v2}-1" "${v1}-1"
check "bump 1 dates its dependent" "$(identity "AIC8800-extra-${SHA_B}" | cut -d' ' -f2)" "${v2}"
pkgmk AIC8800 "${SHA_C}" >packages/drivers/AIC8800/package.mk
commit "2026-11-05T21:10:00Z" "bump 2"
v3="$(identity "AIC8800-${SHA_C}" | cut -d' ' -f2)"
newer "bump 2" "${v3}-1" "${v2}-1"
newer "bump 2 over first" "${v3}-1" "${v1}-1"
# Two bumps within the same minute, to a hash that sorts lower.
pkgmk AIC8800 "${SHA_B}" >packages/drivers/AIC8800/package.mk
commit "2026-11-05T21:10:41Z" "bump 3, same minute"
v4="$(identity "AIC8800-${SHA_B}" | cut -d' ' -f2)"
check "bump 3 pkgver" "${v4}" "1:0.git20261105T211041.a1b2c3d"
newer "bump 3, same minute as bump 2" "${v4}-1" "${v3}-1"
# Same day, later time; next year with an earlier clock.
newer "same day" "1:0.git20261105T211000.0000000-1" "1:0.git20261105T090000.fffffff-1"
newer "next year" "1:0.git20270101T000000.0000000-1" "1:0.git20261231T235959.fffffff-1"

# 3. Transition: the new form beats any bare hash installed today.
newer "transition (AIC8800)" "1:0.git20261104T204530.1018f17-1" "${SHA_A}-1"
for old in "${SHA_A}" "${SHA_B}" ffffffffffffffffffffffffffffffffffffffff 9999999999999999999999999999999999999999; do
    newer "transition from ${old:0:7}, even the fallback date" "1:0.git00000000T000000.0000000-1" "${old}-2"
done

# 4. A normal package keeps its plain version and ordering.
check "normal versions" "$(vercmp 1.3.1-1 1.3.0-1)" 1
check "normal version not git-dated" "$(identity "zlib-1.3.1" | cut -d' ' -f2)" "1.3.1"

# 5. An uncommitted edit dates from the file's mtime (UTC).
pkgmk AIC8800 "${SHA_A}" >packages/drivers/AIC8800/package.mk
touch -d "2026-11-06T03:04:00Z" packages/drivers/AIC8800/package.mk
check "dirty package.mk" "$(identity "AIC8800-${SHA_A}" | cut -d' ' -f2)" "1:0.git20261106T030400.1018f17"
git checkout -q -- packages

# 6. An overlay that sources a base package.mk is dated by the base too.
mkdir -p projects/ArchR/packages/sysutils/udevil packages/sysutils/udevil
pkgmk udevil "${SHA_B}" >packages/sysutils/udevil/package.mk
printf '. ${ROOT}/packages/sysutils/udevil/package.mk\nPKG_TOOLCHAIN="manual"\n' \
    >projects/ArchR/packages/sysutils/udevil/package.mk
commit "2026-11-07T10:00:00Z" "udevil overlay"
u1="$(identity "udevil-${SHA_B}" | cut -d' ' -f2)"
pkgmk udevil "${SHA_A}" >packages/sysutils/udevil/package.mk
commit "2026-11-08T11:30:00Z" "udevil bump in the base"
u2="$(identity "udevil-${SHA_A}" | cut -d' ' -f2)"
check "overlay dated by its base" "${u2}" "1:0.git20261108T113000.1018f17"
newer "overlay bump in the base" "${u2}-1" "${u1}-1"

# 7. gen-pacman-repo publishes only what a package.mk still builds: an
# install_pkg dir left from a renamed or dropped package is skipped.
if command -v repo-add >/dev/null; then
    for d in "AIC8800-${SHA_B}" "zlib-1.3.1" "ppsspp-sa-${SHA_B}" "gone-2.0"; do
        mkdir -p "${TMP}/build/install_pkg/${d}/usr/share/${d}"
        echo "${d}" >"${TMP}/build/install_pkg/${d}/usr/share/${d}/file"
    done
    # OUT_DIR reused from a run of the generator before this change, which
    # published every tree: its stale archives must not reach the new db.
    OLD=7a7346aadf
    mkdir -p "${TMP}/old"
    if git -C "${HERE}" show "${OLD}:scripts/repo/gen-pacman-repo" >"${TMP}/old/gen-pacman-repo" 2>/dev/null &&
       git -C "${HERE}" show "${OLD}:scripts/repo/pkg-identity" >"${TMP}/old/pkg-identity" 2>/dev/null; then
        BUILD_DIR="${TMP}/build" OUT_DIR="${TMP}/out" bash "${TMP}/old/gen-pacman-repo" >/dev/null 2>&1
        check "old generator published the leftovers" "$(cd "${TMP}/out" && ls -1 gone-* ppsspp-sa-* | wc -l)" 2
    else
        echo "skip stale OUT_DIR: commit ${OLD} not available"
    fi
    out="$(BUILD_DIR="${TMP}/build" OUT_DIR="${TMP}/out" bash "$(dirname "${HERE}")/gen-pacman-repo" 2>&1)"
    check "obsolete git-pinned dir skipped" "$(grep -c "ppsspp-sa-${SHA_B}: no package.mk builds it, skipped" <<<"${out}")" 1
    check "obsolete dir skipped" "$(grep -c "gone-2.0: no package.mk builds it, skipped" <<<"${out}")" 1
    check "archives written" "$(cd "${TMP}/out" && ls -1 AIC8800-0.git* zlib-* | tr '\n' ' ')" \
        "AIC8800-0.git20261105T211041.a1b2c3d-1-aarch64.pkg.tar.zst zlib-1.3.1-1-aarch64.pkg.tar.zst "
    check "repo db holds only this run's packages" \
        "$(tar -tzf "${TMP}/out/archr.db.tar.gz" | grep '/desc$' | sort | tr '\n' ' ')" \
        "AIC8800-1:0.git20261105T211041.a1b2c3d-1/desc zlib-1.3.1-1/desc "
    check "seeded local db holds only this run's packages" \
        "$(tar -tzf "${TMP}/out/archr-localdb.tar.gz" | sed -n 's#^local/\([^/]*\)/desc$#\1#p' | sort | tr '\n' ' ')" \
        "AIC8800-1:0.git20261105T211041.a1b2c3d-1 zlib-1.3.1-1 "
else
    echo "skip gen-pacman-repo: repo-add not installed"
fi

# 8. The image db (gen-image-localdb) and the repo (gen-pacman-repo) of
# one build give every package the same version, and the same run-time
# dependencies (PKG_PACMAN_DEPENDS).
printf 'PKG_PACMAN_DEPENDS="glibc coreutils>=9.6-2"\n' >>packages/tools/zlib/package.mk
deps() { tar -xOzf "$1" "$2" | sed -n '/^%DEPENDS%$/,/^$/p' | tr '\n' ' '; }
for d in "AIC8800-${SHA_B}" "zlib-1.3.1" "udevil-${SHA_A}"; do
    n="${d%-*}"
    mkdir -p "${TMP}/build/install_pkg/${d}/usr/share/${n}" "${TMP}/stamps/${n}"
    echo "${d}" >"${TMP}/build/install_pkg/${d}/usr/share/${n}/file"
    printf 'INFO_PKG_NAME="%s"\n' "${n}" >"${TMP}/build/install_pkg/${d}/.archr-package"
    : >"${TMP}/stamps/${n}/install_target"
done
bash "$(dirname "${HERE}")/gen-image-localdb" "${TMP}/build/install_pkg" "${TMP}/stamps" \
    TEST "${TMP}/image-db.tar.gz" >/dev/null
image="$(tar -tzf "${TMP}/image-db.tar.gz" | sed -n 's#^local/\([^/]*\)/desc$#\1#p' | sort | tr '\n' ' ')"
check "image db versions" "${image}" \
    "AIC8800-1:0.git20261105T211041.a1b2c3d-1 udevil-1:0.git20261108T113000.1018f17-1 zlib-1.3.1-1 "
check "image db depends" "$(deps "${TMP}/image-db.tar.gz" local/zlib-1.3.1-1/desc)" \
    "%DEPENDS% glibc coreutils>=9.6-2  "
check "image db: no depends unless asked" "$(tar -xOzf "${TMP}/image-db.tar.gz" --wildcards 'local/AIC8800-*/desc' | grep -c '%DEPENDS%')" 0
if command -v repo-add >/dev/null; then
    rm -rf "${TMP}/out"
    BUILD_DIR="${TMP}/build" OUT_DIR="${TMP}/out" bash "$(dirname "${HERE}")/gen-pacman-repo" >/dev/null 2>&1
    check "repo db versions = image db versions" \
        "$(tar -tzf "${TMP}/out/archr.db.tar.gz" | sed -n 's#^\([^/]*\)/desc$#\1#p' | sort | tr '\n' ' ')" "${image}"
    check "repo db depends = image db depends" "$(deps "${TMP}/out/archr.db.tar.gz" zlib-1.3.1-1/desc)" \
        "%DEPENDS% glibc coreutils>=9.6-2  "
fi

# 9. Without the full history (a source tarball, a shallow clone) both
# generators stop; ARCHR_PKGVER_ALLOW_NOGIT=1 allows a placeholder date.
mkdir -p "${TMP}/tarball"
cp -r "${SRC}/packages" "${SRC}/projects" "${TMP}/tarball/"
git clone -q --depth 1 "file://${SRC}" "${TMP}/shallow"
for ctx in tarball shallow; do
    for gen in gen-image-localdb gen-pacman-repo; do
        if [ "${gen}" = gen-image-localdb ]; then
            args=("${TMP}/build/install_pkg" "${TMP}/stamps" TEST "${TMP}/${ctx}-image.tar.gz")
        else
            args=()
        fi
        out="$(cd "${TMP}/${ctx}" && GIT_CEILING_DIRECTORIES="${TMP}" BUILD_DIR="${TMP}/build" \
                OUT_DIR="${TMP}/${ctx}-out" bash "$(dirname "${HERE}")/${gen}" "${args[@]}" 2>&1)"
        check "${ctx}: ${gen} refuses" "$?:$(grep -c 'need the full history' <<<"${out}")" "1:1"
    done
    check "${ctx}: allowed fallback" "$(cd "${TMP}/${ctx}" && GIT_CEILING_DIRECTORIES="${TMP}" \
        ARCHR_PKGVER_ALLOW_NOGIT=1 bash -c ". '${IDENTITY}' 2>/dev/null; pkg_git_pkgver ${SHA_C} packages/drivers/AIC8800/package.mk")" \
        "1:0.git00000000T000000.0000000"
    check "${ctx}: allowed fallback warns" "$(cd "${TMP}/${ctx}" && GIT_CEILING_DIRECTORIES="${TMP}" \
        ARCHR_PKGVER_ALLOW_NOGIT=1 bash -c ". '${IDENTITY}'" 2>&1 | grep -c 'do not publish')" 1
done

[ "${FAILED}" = 0 ] && echo "PASS" || { echo "FAILED"; exit 1; }
