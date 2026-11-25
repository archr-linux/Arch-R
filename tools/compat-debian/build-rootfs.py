#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# build-rootfs.py: the Debian runtime of the dArkOS compatibility mode
# (archr-compat-debian), built on a PC with no debootstrap, qemu or root.
#
# dArkOS and dArkOSen are Debian 13 (Trixie). This resolves the packages
# in packages.list against a Debian archive (a snapshot.debian.org date
# makes the result reproducible), checks every file against the signed
# Release (gpgv + the Debian keyring when given, else HTTPS only), unpacks
# the data of each .deb into a merged-/usr tree, and writes the dpkg
# database so apt works later inside the runtime. Maintainer scripts never
# run: the runtime is libraries and tools, the few things a postinst would
# do are done in fixups() and overlay/.
#
#   build-rootfs.py --out DIR [--suite trixie] [--arch arm64[,armhf]]
#                   [--snapshot 20261120T000000Z] [--keyring FILE]
#                   [--cache DIR] [--packages FILE] [--overlay DIR]

import argparse
import gzip
import hashlib
import io
import lzma
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

try:
    from compression import zstd  # Python 3.14
except ImportError:  # pragma: no cover
    zstd = None

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {"User-Agent": "archr-compat-debian-builder"}


def log(*a):
    print("build-rootfs:", *a, file=sys.stderr, flush=True)


def fetch(url, dest=None):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if dest:
        tmp = dest + ".part"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
    return data


def sha256(data):
    return hashlib.sha256(data).hexdigest()


# ---- Debian version comparison (dpkg's algorithm) -------------------------

def _order(c):
    if c.isdigit():
        return 0
    if c.isalpha():
        return ord(c)
    if c == "~":
        return -1
    return ord(c) + 256


def _cmp_part(a, b):
    i = j = 0
    while i < len(a) or j < len(b):
        first_diff = 0
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ac = _order(a[i]) if i < len(a) else 0
            bc = _order(b[j]) if j < len(b) else 0
            if ac != bc:
                return ac - bc
            i += 1
            j += 1
        while i < len(a) and a[i] == "0":
            i += 1
        while j < len(b) and b[j] == "0":
            j += 1
        while i < len(a) and a[i].isdigit() and j < len(b) and b[j].isdigit():
            if not first_diff:
                first_diff = ord(a[i]) - ord(b[j])
            i += 1
            j += 1
        if i < len(a) and a[i].isdigit():
            return 1
        if j < len(b) and b[j].isdigit():
            return -1
        if first_diff:
            return first_diff
    return 0


def vercmp(x, y):
    def split(v):
        e, _, rest = v.partition(":") if ":" in v else ("0", "", v)
        up, _, rev = rest.rpartition("-") if "-" in rest else (rest, "", "0")
        return int(e or 0), up, rev
    ex, ux, rx = split(x)
    ey, uy, ry = split(y)
    if ex != ey:
        return ex - ey
    return _cmp_part(ux, uy) or _cmp_part(rx, ry)


# ---- Archive indexes ------------------------------------------------------

def parse_stanzas(text):
    for block in text.split("\n\n"):
        if not block.strip():
            continue
        st, key = {}, None
        for line in block.splitlines():
            if line[:1] in (" ", "\t") and key:
                st[key] += "\n" + line
            elif ":" in line:
                key, _, val = line.partition(":")
                st[key] = val.strip()
        yield st


def release_hashes(text):
    out, on = {}, False
    for line in text.splitlines():
        if line.startswith("SHA256:"):
            on = True
            continue
        if on:
            if not line.startswith(" "):
                on = False
                continue
            h, size, name = line.split()
            out[name] = (h, int(size))
    return out


def verify_release(data, keyring, cache, name):
    path = os.path.join(cache, name)
    with open(path, "wb") as f:
        f.write(data)
    if not keyring:
        log("WARNING: no --keyring, %s checked by HTTPS only" % name)
        return data.decode()
    out = subprocess.run(["gpgv", "--keyring", keyring, "--output", "-", path],
                         check=True, capture_output=True)
    return out.stdout.decode()


def load_index(base, suite, arch, keyring, cache):
    tag = re.sub(r"[^A-Za-z0-9]+", "_", base + "_" + suite + "_" + arch)
    rel = fetch("%s/dists/%s/InRelease" % (base, suite))
    text = verify_release(rel, keyring, cache, tag + ".InRelease")
    hashes = release_hashes(text)
    name = "main/binary-%s/Packages.xz" % arch
    if name not in hashes:
        raise SystemExit("%s: no %s" % (suite, name))
    data = fetch("%s/dists/%s/%s" % (base, suite, name))
    if sha256(data) != hashes[name][0]:
        raise SystemExit("%s: %s hash mismatch" % (suite, name))
    pkgs = {}
    for st in parse_stanzas(lzma.decompress(data).decode()):
        st["_base"] = base
        old = pkgs.get(st["Package"])
        if old is None or vercmp(st["Version"], old["Version"]) > 0:
            pkgs[st["Package"]] = st
    return pkgs


# ---- Resolution -----------------------------------------------------------

def dep_groups(st):
    for field in ("Pre-Depends", "Depends"):
        for group in filter(None, (g.strip() for g in st.get(field, "").split(","))):
            alts = []
            for alt in group.split("|"):
                m = re.match(r"\s*([^\s(:\[]+)(:[a-z0-9]+)?", alt)
                if m:
                    alts.append((m.group(1), m.group(2)))
            yield alts


def resolve(wanted, indexes, primary, exclude):
    """wanted: [(name, arch)]. indexes: arch -> {name: stanza}."""
    provides = {}
    for arch, pk in indexes.items():
        for st in pk.values():
            for p in filter(None, (x.strip() for x in st.get("Provides", "").split(","))):
                provides.setdefault((p.split()[0], arch), []).append(st["Package"])
    chosen, stood_in, queue = {}, {}, list(wanted)
    while queue:
        name, arch = queue.pop()
        if name in exclude:
            if name in indexes[arch]:
                stood_in[(name, arch)] = indexes[arch][name]["Version"]
            continue
        if (name, arch) in chosen:
            continue
        st = indexes[arch].get(name)
        if st is None:
            real = provides.get((name, arch))
            if not real:
                raise SystemExit("not in the archive: %s:%s" % (name, arch))
            queue.append((sorted(real)[0], arch))
            continue
        chosen[(name, arch)] = st
        for alts in dep_groups(st):
            pick = None
            for dname, qual in alts:
                darch = primary if qual == ":any" or st.get("Architecture") == "all" else arch
                if qual and qual not in (":any", ":native"):
                    darch = qual[1:]
                if (dname, darch) in chosen or dname in indexes[darch] or (dname, darch) in provides:
                    pick = (dname, darch)
                    break
            if pick is None:
                raise SystemExit("unresolvable for %s: %s" % (name, alts))
            # Architecture: all packages and Multi-Arch: foreign deps come
            # from the primary architecture.
            dst = indexes[pick[1]].get(pick[0])
            if dst and dst.get("Multi-Arch") == "foreign":
                pick = (pick[0], primary)
            queue.append(pick)
    return chosen, stood_in


# ---- Unpacking ------------------------------------------------------------

def ar_members(data):
    if data[:8] != b"!<arch>\n":
        raise ValueError("not an ar archive")
    pos = 8
    while pos < len(data):
        hdr = data[pos:pos + 60]
        name = hdr[:16].decode().strip().rstrip("/")
        size = int(hdr[48:58].decode().strip())
        pos += 60
        yield name, data[pos:pos + size]
        pos += size + (size & 1)


def decompress(name, blob):
    if name.endswith(".xz"):
        return lzma.decompress(blob)
    if name.endswith(".gz"):
        return gzip.decompress(blob)
    if name.endswith(".zst"):
        if zstd:
            return zstd.decompress(blob)
        return subprocess.run(["zstd", "-dc"], input=blob, check=True, capture_output=True).stdout
    if name.endswith(".tar"):
        return blob
    raise ValueError("unknown compression: " + name)


MERGED = (("./bin/", "./usr/bin/"), ("./sbin/", "./usr/sbin/"), ("./lib/", "./usr/lib/"),
          ("./lib64/", "./usr/lib64/"), ("./lib32/", "./usr/lib32/"))


MERGED_ROOTS = tuple(b.rstrip("/") for _, b in MERGED)


def merged(path):
    p = "./" + path.lstrip("./") if not path.startswith("./") else path
    for a, b in MERGED:
        if p.startswith(a) or p + "/" == a:
            return b + p[len(a):]
    return p


def safe(root, rel):
    full = os.path.normpath(os.path.join(root, rel))
    if not (full == root or full.startswith(root + os.sep)):
        raise ValueError("path outside the root: " + rel)
    return full


def unpack(deb, root):
    files, control = [], {}
    for name, blob in ar_members(deb):
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(decompress(name, blob))) as t:
                for m in t.getmembers():
                    if m.isfile():
                        control[os.path.basename(m.name)] = t.extractfile(m).read()
        elif name.startswith("data.tar"):
            with tarfile.open(fileobj=io.BytesIO(decompress(name, blob))) as t:
                for m in t.getmembers():
                    rel = merged(m.name)
                    dst = safe(root, rel)
                    files.append("/" + rel[2:].rstrip("/") if rel.strip("./") else "/.")
                    if m.isdir():
                        if os.path.islink(dst):
                            continue
                        os.makedirs(dst, exist_ok=True)
                        os.chmod(dst, (m.mode & 0o7777) | 0o700)
                        continue
                    if m.issym() and rel.rstrip("/") in MERGED_ROOTS:
                        # /bin -> usr/bin and the like: already merged here.
                        continue
                    if m.issym() and os.path.isdir(dst) and not os.path.islink(dst):
                        # A link where an earlier package made a folder
                        # (/var/run -> /run): the link wins, as in dpkg.
                        shutil.rmtree(dst)
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    if os.path.lexists(dst) and not os.path.isdir(dst):
                        os.unlink(dst)
                    if m.issym():
                        os.symlink(m.linkname, dst)
                    elif m.islnk():
                        os.link(safe(root, merged(m.linkname)), dst)
                    elif m.isfile():
                        with open(dst, "wb") as f:
                            shutil.copyfileobj(t.extractfile(m), f)
                        os.chmod(dst, m.mode & 0o7777)
                    # Device nodes and fifos: none in the runtime (/dev is bound).
    return files, control


# ---- Fixups a postinst would have done ------------------------------------

def fixups(root):
    def link(target, name):
        p = os.path.join(root, name)
        if not os.path.lexists(p) and os.path.exists(os.path.join(root, os.path.dirname(name), target)):
            os.symlink(target, p)
    link("dash", "usr/bin/sh")
    link("mawk", "usr/bin/awk")
    link("which.debianutils", "usr/bin/which")
    link("less", "usr/bin/pager")
    link("python3", "usr/bin/python")
    for name, target in (("var/run", "/run"), ("var/lock", "/run/lock")):
        p = os.path.join(root, name)
        if not os.path.islink(p):
            shutil.rmtree(p, ignore_errors=True)
            os.symlink(target, p)


def strip_docs(root):
    """What dpkg.cfg.d/01archr-nodoc keeps out of later installs too.
    The copyright files stay (licenses)."""
    share = os.path.join(root, "usr/share")
    for d in ("man", "info", "locale", "lintian", "linda"):
        shutil.rmtree(os.path.join(share, d), ignore_errors=True)
    doc = os.path.join(share, "doc")
    for top, dirs, files in os.walk(doc):
        for f in files:
            if f != "copyright":
                os.unlink(os.path.join(top, f))


def drop_deps(field, names):
    """A Depends field without the packages left out (!name): apt then
    sees a consistent system, and installing one of them later works."""
    groups = []
    for group in field.split(","):
        alts = [re.match(r"\s*([^\s(:\[]+)", x).group(1) for x in group.split("|")]
        # The left-out package was what satisfied this group: it goes whole.
        if not any(a in names for a in alts):
            groups.append(group.strip())
    return ", ".join(groups)


def write_dpkg_db(root, chosen, lists, controls, stood_in, exclude, dropped):
    info = os.path.join(root, "var/lib/dpkg/info")
    os.makedirs(info, exist_ok=True)
    for f in ("available", "diversions", "statoverride"):
        open(os.path.join(root, "var/lib/dpkg", f), "a").close()
    for d in ("updates", "triggers", "alternatives"):
        os.makedirs(os.path.join(root, "var/lib/dpkg", d), exist_ok=True)
    skip = {"Filename", "Size", "MD5sum", "SHA256", "SHA1", "Description-md5", "_base", "Tag"}
    out = []
    for (name, arch), st in sorted(chosen.items()):
        lines = ["Package: " + name, "Status: install ok installed"]
        for k, v in st.items():
            if k in skip or k == "Package":
                continue
            if k in ("Depends", "Pre-Depends"):
                v = drop_deps(v, dropped)
                if not v:
                    continue
            lines.append("%s: %s" % (k, v))
        out.append("\n".join(lines))
        qual = name + (":" + st["Architecture"] if st.get("Multi-Arch") == "same" else "")
        with open(os.path.join(info, qual + ".list"), "w") as f:
            f.write("\n".join(sorted(set(lists[(name, arch)]))) + "\n")
        for k in ("md5sums", "conffiles", "shlibs", "symbols"):
            if k in controls[(name, arch)]:
                with open(os.path.join(info, qual + "." + k), "wb") as f:
                    f.write(controls[(name, arch)][k])
    # What packages.list keeps out but installed packages depend on (GL,
    # GBM: Arch R's at run time) is "provided" by one stand-in per
    # architecture, at the archive's version, so apt sees no broken
    # dependency and never installs the real ones over Arch R's.
    provided = {k: v for k, v in stood_in.items() if exclude.get(k[0]) == "="}
    for arch in sorted({a for _, a in provided}):
        names = sorted((n, v) for (n, a), v in provided.items() if a == arch)
        out.append("\n".join([
            "Package: archr-host-provided", "Status: install ok installed",
            "Priority: optional", "Section: misc", "Installed-Size: 0",
            "Maintainer: Arch R <https://arch-r.io>", "Architecture: " + arch,
            "Multi-Arch: same", "Version: 1",
            "Provides: " + ", ".join("%s (= %s)" % nv for nv in names),
            "Description: supplied by Arch R to the compatibility runtime",
            " GL, GBM and the like come from the Arch R system at run time."]))
    with open(os.path.join(root, "var/lib/dpkg/status"), "w") as f:
        f.write("\n\n".join(out) + "\n")


MOUNTPOINTS = (".host", ".archr", "storage", "run", "proc", "sys", "dev", "tmp", "flash")


def copy_overlay(src, root):
    """Our files win over the packages', a link over a directory too."""
    for top, dirs, files in os.walk(src):
        rel = os.path.relpath(top, src)
        for name in sorted(dirs + files):
            s = os.path.join(top, name)
            d = safe(root, os.path.join(rel, name))
            if os.path.islink(s) or not os.path.isdir(s):
                if os.path.isdir(d) and not os.path.islink(d):
                    shutil.rmtree(d)
                elif os.path.lexists(d):
                    os.unlink(d)
                if os.path.islink(s):
                    os.symlink(os.readlink(s), d)
                else:
                    shutil.copy2(s, d)
            elif os.path.islink(d) or not os.path.isdir(d):
                if os.path.lexists(d):
                    os.unlink(d)
                os.makedirs(d)
        dirs[:] = [x for x in dirs if not os.path.islink(os.path.join(top, x))]


def read_list(path):
    items = []
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if line:
            items.extend(line.split())
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--suite", default="trixie")
    ap.add_argument("--arch", default="arm64")
    ap.add_argument("--snapshot", help="snapshot.debian.org timestamp, e.g. 20261120T000000Z")
    ap.add_argument("--mirror", default="https://deb.debian.org")
    ap.add_argument("--keyring", help="Debian archive keyring (gpgv) for InRelease")
    ap.add_argument("--cache", default=os.path.join(HERE, ".cache"))
    ap.add_argument("--packages", default=os.path.join(HERE, "packages.list"))
    ap.add_argument("--overlay", default=os.path.join(HERE, "overlay"))
    a = ap.parse_args()

    arches = a.arch.split(",")
    primary = arches[0]
    if a.snapshot:
        bases = ["https://snapshot.debian.org/archive/debian/" + a.snapshot,
                 "https://snapshot.debian.org/archive/debian-security/" + a.snapshot]
    else:
        bases = [a.mirror + "/debian", a.mirror + "/debian-security"]
    suites = [(bases[0], a.suite), (bases[0], a.suite + "-updates"), (bases[1], a.suite + "-security")]
    os.makedirs(a.cache, exist_ok=True)

    indexes = {}
    for arch in arches:
        merged_idx = {}
        for base, suite in suites:
            for name, st in load_index(base, suite, arch, a.keyring, a.cache).items():
                old = merged_idx.get(name)
                if old is None or vercmp(st["Version"], old["Version"]) > 0:
                    merged_idx[name] = st
        indexes[arch] = merged_idx
        log("%s: %d packages in the index" % (arch, len(merged_idx)))

    wanted, exclude = [], {}
    for item in read_list(a.packages):
        if item[:1] in ("!", "="):
            exclude[item[1:]] = item[0]
            continue
        name, _, arch = item.partition(":")
        for ar in (arches if arch == "*" else [arch or primary]):
            if ar in arches:
                wanted.append((name, ar))
    # Essential packages are never declared as dependencies (perl-base for
    # update-rc.d...): they always go in, as debootstrap does.
    wanted += [(n, primary) for n, st in indexes[primary].items()
               if st.get("Essential") == "yes" and n not in exclude]
    chosen, stood_in = resolve(wanted, indexes, primary, exclude)
    # Every =name is provided, depended on now or by a later apt install.
    for n, kind in exclude.items():
        if kind == "=" and n in indexes[primary]:
            stood_in[(n, primary)] = indexes[primary][n]["Version"]
    total = sum(int(st.get("Installed-Size", 0)) for st in chosen.values())
    log("%d packages, ~%d MiB installed" % (len(chosen), total // 1024))

    root = os.path.abspath(a.out)
    if os.path.exists(root):
        raise SystemExit("output exists: " + root)
    os.makedirs(root)
    for d in ("usr/bin", "usr/sbin", "usr/lib"):
        os.makedirs(os.path.join(root, d))
    for l, t in (("bin", "usr/bin"), ("sbin", "usr/sbin"), ("lib", "usr/lib")):
        os.symlink(t, os.path.join(root, l))

    lists, controls = {}, {}
    for key in sorted(chosen):
        st = chosen[key]
        cached = os.path.join(a.cache, st["SHA256"] + ".deb")
        if os.path.exists(cached):
            deb = open(cached, "rb").read()
        else:
            deb = fetch(st["_base"] + "/" + st["Filename"])
            if sha256(deb) != st["SHA256"]:
                raise SystemExit("hash mismatch: " + st["Filename"])
            with open(cached, "wb") as f:
                f.write(deb)
        if sha256(deb) != st["SHA256"]:
            raise SystemExit("cached hash mismatch: " + cached)
        lists[key], controls[key] = unpack(deb, root)

    fixups(root)
    strip_docs(root)
    # Left out (!name): the package and the virtual names only it provides.
    dropped = {n for n, kind in exclude.items() if kind == "!"}
    for arch in arches:
        for n in list(dropped):
            st = indexes[arch].get(n, {})
            for p in filter(None, (x.strip() for x in st.get("Provides", "").split(","))):
                dropped.add(p.split()[0])
    write_dpkg_db(root, chosen, lists, controls, stood_in, exclude, dropped)
    if os.path.isdir(a.overlay):
        copy_overlay(a.overlay, root)
    # Mount points archr-compat-debian binds Arch R paths on.
    for d in MOUNTPOINTS:
        os.makedirs(os.path.join(root, d), exist_ok=True)
    with open(os.path.join(root, "etc/archr-compat-packages"), "w") as f:
        for (name, arch), st in sorted(chosen.items()):
            f.write("%s:%s %s\n" % (name, arch, st["Version"]))
    log("done: " + root)


if __name__ == "__main__":
    main()
