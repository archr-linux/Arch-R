# scripts/repo

Tooling for the GitHub-Releases-as-pacman-mirror workflow described in
`docs/release-policy.md`. The end result is a tag like `repo-stable`
on `archr-linux/archr-repo` with the assembled `.pkg.tar.zst` files
and signed metadata.

## gen-pacman-repo

Reads the finished build tree (`build.*-RK3326/install_pkg/<pkg>/`)
that `make docker-RK3326` leaves behind, packs each `<pkg>` directory
into a `<pkg>-<version>-1-aarch64.pkg.tar.zst`, generates the
`.PKGINFO` sidecar that pacman needs, and runs `repo-add` to build
`archr.db` and `archr.files`.

Run after a successful build:

```sh
BUILD_DIR=build.ArchR-RK3326.aarch64-2026.06-devel \
OUT_DIR=/tmp/repo-out \
CHANNEL=dev \
SIGNER=                                          \
    scripts/repo/gen-pacman-repo
```

Then upload:

```sh
gh release create repo-dev                                \
    --repo archr-linux/archr-repo                         \
    --title "ArchR repo dev $(date +%Y%m%d)"              \
    /tmp/repo-out/*
```

## GPG signing

For production releases, set `SIGNER=<fingerprint>` and have the
agent (or a YubiKey-backed agent) ready. `repo-add --sign` will sign
the .db as it walks the package list, and each .pkg.tar.zst gets a
.sig as well.

The master key whose public half is bundled into the `archr-keyring`
package must include `<fingerprint>` either directly or as a signed
subkey, otherwise `pacman-key --populate archr` on the client will
not extend trust to packages signed by it.

## Channels and tag mapping

`archr-update` rewrites `/etc/pacman.d/mirrorlist` based on
`system.cfg "updates.branch"`:

| Channel value | Mirror tag on archr-linux/archr-repo |
|---------------|--------------------------------------|
| `stable` (default) | `repo-stable` |
| `next`        | `repo-next` |
| `dev`         | `repo-dev` |

The promotion workflow (dev -> next -> stable) is documented in
`docs/release-policy.md`.

## Release notes (optional)

`archr-update check --json` shows a release's notes on the launcher's
Updates page when the release carries a `changelog.txt` asset next to
the repo (`repo-<channel>/changelog.txt`). Its first line is the version
the release brings (for example `2.1.2`); the following lines are the
notes, in plain text. Without the asset the page simply has no notes.

## Versions of git-pinned packages

A package.mk whose `PKG_VERSION` is a 40-hex commit (367 of them today:
the libretro cores, the WiFi drivers such as `AIC8800` and `RTL8821CU`,
`archr-launcher`, `retroarch`, ...) cannot use that hash as its pacman
version: `vercmp` orders hashes arbitrarily, so a bump to a hash that
sorts lower was taken for a downgrade and never offered. `pkg-identity`
publishes such a package as

    1:0.git<YYYYMMDD>T<HHMM>.<sha7>     e.g. 1:0.git20261104T2045.1018f17

where the date is the UTC committer date of the last first-parent commit
that changed its package.mk (and, for `$(get_pkg_version X)`, X's), so
every bump sorts higher. Epoch 1 puts it above every bare hash already
installed, so the first release with this scheme offers each of these
packages once. An uncommitted package.mk is dated by its mtime; a tree
without git history (a source tarball) uses `00000000T0000`, older than
any real date, and is not meant for publishing. `PKG_VERSION` itself is
unchanged: source URLs, build directories and stamps still use the hash.
Archive names leave the epoch out (GitHub rewrites `:` in asset names).
`bash scripts/repo/tests/pkg_identity_test.sh` checks the ordering.

`gen-pacman-repo` skips an `install_pkg/` tree that no package.mk builds
any more (a build dir keeps trees of renamed or dropped packages, such as
the old `*-sa` emulators); the packages that replace them carry
`PKG_REPLACES`.
