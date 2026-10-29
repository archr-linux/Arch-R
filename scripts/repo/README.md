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
