#!/bin/bash
# Host test for gen-offline-update: from a small fake repo and two fake image
# dbs, the bundle holds exactly the packages whose version is not the same in
# every base, with the manifest, the db and its signature at the top level
# under the names archr-update accepts; a missing package file or a missing
# base fails and leaves no bundle behind.
#   bash scripts/repo/tests/gen_offline_update_test.sh

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GEN="$(dirname "${HERE}")/gen-offline-update"
UPDATE="${HERE}/../../../projects/ArchR/packages/archr/sources/scripts/archr-update"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0

check() { # name got want
    if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     got:      $2"; echo "     expected: $3"; FAILED=1; fi
}

bash -n "${GEN}" && echo "ok   bash -n" || { echo "FAIL bash -n"; FAILED=1; }

# desc DIR NAME VERSION [FILENAME]
desc() {
    mkdir -p "$1"
    {
        [ -n "${4:-}" ] && printf '%%FILENAME%%\n%s\n\n' "$4"
        printf '%%NAME%%\n%s\n\n%%VERSION%%\n%s\n\n%%DESC%%\nx\n\n' "$2" "$3"
    } >"$1/desc"
}
# The repo: a same everywhere, b changed in one base, c new, d changed in
# both, e (git-pinned, with an epoch) same everywhere.
REPO="${TMP}/repo-out"
mkdir -p "${REPO}" "${TMP}/db"
for p in "a 1.0-1" "b 2.0-1" "c 1.0-1" "d 3.0-2" "e 1:0.git20261104T204530.1018f17-1"; do
    set -- ${p}
    file="$1-${2#*:}-aarch64.pkg.tar.zst"   # archive names drop the epoch
    desc "${TMP}/db/$1-$2" "$1" "$2" "${file}"
    echo "$1" >"${REPO}/${file}"
done
# An older file the db no longer lists.
echo old >"${REPO}/b-1.0-1-aarch64.pkg.tar.zst"
tar -C "${TMP}/db" -czf "${REPO}/archr.db.tar.gz" .
ln -s archr.db.tar.gz "${REPO}/archr.db"
echo signature >"${REPO}/archr.db.tar.gz.sig"
printf '20261113.4\n\n- System: fix.\n' >"${REPO}/changelog.txt"

# Base 1 as gen-pacman-repo seeds it; base 2 as the image db (with its build).
desc "${TMP}/b1/local/a-1.0-1" a 1.0-1
desc "${TMP}/b1/local/b-2.0-1" b 2.0-1
desc "${TMP}/b1/local/d-3.0-1" d 3.0-1
desc "${TMP}/b1/local/e-1:0.git20261104T204530.1018f17-1" e 1:0.git20261104T204530.1018f17-1
echo 9 >"${TMP}/b1/local/ALPM_DB_VERSION"
tar -C "${TMP}/b1" -czf "${TMP}/base1.tar.gz" local
desc "${TMP}/b2/local/a-1.0-1" a 1.0-1
desc "${TMP}/b2/local/b-1.0-1" b 1.0-1
desc "${TMP}/b2/local/d-3.0-1" d 3.0-1
desc "${TMP}/b2/local/e-1:0.git20261104T204530.1018f17-1" e 1:0.git20261104T204530.1018f17-1
echo abc >"${TMP}/b2/archr-image-build"
tar -C "${TMP}/b2" -czf "${TMP}/base2.tar.gz" local archr-image-build

OUT="${TMP}/out/archr-update-20261113.4.tar"
MSG=$(REPO_DIR="${REPO}" OUT="${OUT}" BASE_DBS="${TMP}/base1.tar.gz ${TMP}/base2.tar.gz" bash "${GEN}" 2>&1)
check "generator exits 0" "$?" 0
check "it prints the id and the count" "$(grep -o 'update 20261113.4 (stable), 3 packages' <<<"${MSG}")" "update 20261113.4 (stable), 3 packages"
check "entries: manifest first, then the fixed files, then the packages" "$(tar -tf "${OUT}" | tr '\n' ' ')" \
    "archr-update.txt changelog.txt archr.db archr.db.sig b-2.0-1-aarch64.pkg.tar.zst c-1.0-1-aarch64.pkg.tar.zst d-3.0-2-aarch64.pkg.tar.zst "
check "all entries are regular files" "$(tar -tvf "${OUT}" | cut -c1 | sort -u | tr -d '\n')" "-"
check "manifest" "$(tar -xOf "${OUT}" archr-update.txt | sed 's/^created=[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]\{8\}Z$/created=OK/' | tr '\n' ' ')" \
    "id=20261113.4 channel=stable created=OK "
check "archr.db is the db itself" "$(tar -xOf "${OUT}" archr.db | cmp - "${REPO}/archr.db.tar.gz" && echo same)" same
check "archr.db.sig is its signature" "$(tar -xOf "${OUT}" archr.db.sig)" signature
check "package content" "$(tar -xOf "${OUT}" c-1.0-1-aarch64.pkg.tar.zst)" c
# Every entry has a name archr-update takes.
eval "$(grep '^BUNDLE_ENTRY=' "${UPDATE}")"
bad=""
while read -r e; do [[ ${e} =~ ${BUNDLE_ENTRY} ]] || bad="${bad} ${e}"; done < <(tar -tf "${OUT}")
check "archr-update accepts every entry" "${bad}" ""
check "no temporary file left" "$(ls -A "${TMP}/out" | tr '\n' ' ')" "archr-update-20261113.4.tar "

# Positional arguments, one base: e is the same, the rest differs from base 2.
bash "${GEN}" "${REPO}" "${TMP}/one.tar" "${TMP}/base2.tar.gz" >/dev/null 2>&1
check "one base, positional arguments" "$(tar -tf "${TMP}/one.tar" | grep -c pkg.tar.zst)" 3
CHANNEL=next bash "${GEN}" "${REPO}" "${TMP}/next.tar" "${TMP}/base1.tar.gz" >/dev/null 2>&1
check "channel" "$(tar -xOf "${TMP}/next.tar" archr-update.txt | sed -n 's/^channel=//p')" next

rm "${REPO}/c-1.0-1-aarch64.pkg.tar.zst"
MSG=$(bash "${GEN}" "${REPO}" "${TMP}/fail.tar" "${TMP}/base1.tar.gz" 2>&1)
check "missing package file: fails" "$?" 1
check "missing package file: says which" "$(grep -o 'missing in .*' <<<"${MSG}" | sed 's#.*: ##')" "c-1.0-1-aarch64.pkg.tar.zst"
check "missing package file: no bundle" "$(ls "${TMP}" | grep -c 'fail.tar')" 0
echo c >"${REPO}/c-1.0-1-aarch64.pkg.tar.zst"

MSG=$(REPO_DIR="${REPO}" OUT="${TMP}/nobase.tar" bash "${GEN}" 2>&1)
check "no base: fails" "$?|$(grep -c 'BASE_DBS' <<<"${MSG}")" "1|1"
mv "${REPO}/archr.db.tar.gz.sig" "${TMP}/sig"
MSG=$(bash "${GEN}" "${REPO}" "${TMP}/nosig.tar" "${TMP}/base1.tar.gz" 2>&1)
check "unsigned db: fails" "$?|$(grep -c 'signature' <<<"${MSG}")" "1|1"
mv "${TMP}/sig" "${REPO}/archr.db.tar.gz.sig"
echo "not-an-id" >"${REPO}/changelog.txt"
MSG=$(bash "${GEN}" "${REPO}" "${TMP}/noid.tar" "${TMP}/base1.tar.gz" 2>&1)
check "changelog without an id: fails" "$?" 1

exit ${FAILED}
