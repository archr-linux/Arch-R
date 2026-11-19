#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# archr-boot-tuning against a scratch root: the stock table kept, the CPU
# overlay's voltages, extlinux.conf listing it once, the neutral overlay
# for 0, the range, and a revert told once.
#   bash tests/boot_tuning_test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=${HERE}/../sources/scripts/archr-boot-tuning
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }
expect() { [ "$2" = "$3" ] || fail "$1: got '$3', expected '$2'"; }
export ARCHR_TUNING_ROOT=${TMP}
mkdir -p "${TMP}/flash/extlinux" "${TMP}/flash/overlays" "${TMP}/bin"
printf '#!/bin/sh\necho "$@" >>%s/toasts\n' "${TMP}" >"${TMP}/bin/archr-toast"
chmod +x "${TMP}/bin/archr-toast"
export PATH=${TMP}/bin:${PATH}
printf 'LABEL ArchR\n  LINUX /KERNEL\n  FDTDIR /dtbs/\n  FDTOVERLAYS /overlays/mipi-panel.dtbo\n  APPEND x\n' \
  >"${TMP}/flash/extlinux/extlinux.conf"
python3 -I - "${TMP}" <<'PY'
import os, struct, sys
base = sys.argv[1] + "/proc/device-tree/opp-table-0"
for hz, uv in [(408, (950000, 950000, 1350000)), (1416, (1350000, 1350000, 1350000)),
               (1512, (1400000, 1400000, 1400000))]:
    os.makedirs(f"{base}/opp-{hz}000000")
    open(f"{base}/opp-{hz}000000/opp-microvolt", "wb").write(struct.pack(">3I", *uv))
PY
run() { python3 -I "${TOOL}" "$@"; }
field() { python3 -I -c 'import json,sys; v=json.load(sys.stdin)
for p in sys.argv[1].split("."): v=v[p]
print(v)' "$1"; }
# The voltages an overlay sets, read back from its blob.
voltages() {
  python3 -I - "$1" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
off_struct, off_str = struct.unpack(">II", b[8:16])
strings = b[off_str:]
i, out = off_struct, []
while True:
    tok = struct.unpack(">I", b[i:i+4])[0]; i += 4
    if tok == 1:
        end = b.index(b"\0", i); i = (end + 4) & ~3
    elif tok == 3:
        ln, no = struct.unpack(">II", b[i:i+8]); i += 8
        name = strings[no:strings.index(b"\0", no)].decode()
        if name == "opp-microvolt":
            out.append(",".join(str(v) for v in struct.unpack(">%dI" % (ln // 4), b[i:i+ln])))
        i = (i + ln + 3) & ~3
    elif tok == 2:
        pass
    elif tok == 9:
        break
print(" ".join(out))
PY
}

expect "stock read" "950000" "$(run status | field stock.opp-408000000 | tr -d '[] ' | cut -d, -f1)"
expect "lower 25" "True" "$(run cpu -25 | field ok)"
expect "overlay -25" "925000,925000,1350000 1325000,1325000,1350000 1375000,1375000,1400000" \
  "$(voltages "${TMP}/flash/overlays/tuning.dtbo")"
expect "listed once" "1" "$(grep -c tuning.dtbo "${TMP}/flash/extlinux/extlinux.conf")"
expect "after the panel" "  FDTOVERLAYS /overlays/mipi-panel.dtbo /overlays/tuning.dtbo" \
  "$(grep FDTOVERLAYS "${TMP}/flash/extlinux/extlinux.conf")"
expect "pending" "True" "$(run status | field pending_reboot)"
# The running tree now carries the tuning: the stock kept in /flash stays.
run cpu -40 >/dev/null
expect "from stock" "910000,910000,1350000" "$(voltages "${TMP}/flash/overlays/tuning.dtbo" | cut -d' ' -f1)"
expect "range" "out_of_range" "$(run cpu -45 | field error)"
expect "step" "out_of_range" "$(run cpu -12 | field error)"
run reset >/dev/null
expect "neutral" "True" "$(run status | field neutral)"
expect "listed once after reset" "1" "$(grep -c tuning.dtbo "${TMP}/flash/extlinux/extlinux.conf")"
# The initramfs reverted: told once, kept in the status.
run cpu -30 >/dev/null
cp "${TMP}/flash/overlays/tuning.neutral.dtbo" "${TMP}/flash/overlays/tuning.dtbo"
echo 2 >"${TMP}/flash/tuning.reverted"
expect "revert told" "True" "$(run boot | field reverted)"
expect "once" "False" "$(run boot | field reverted)"
expect "one toast" "1" "$(wc -l <"${TMP}/toasts")"
expect "in English without a language" "error errors Voltage tuning undone: the console froze twice Stock voltages restored" \
  "$(cat "${TMP}/toasts")"
expect "status keeps it" "2" "$(run status | field reverted)"
expect "offset back to 0" "0" "$(run status | field cpu_offset_mv)"
[ ${FAILED} -eq 0 ] && echo "ok   archr-boot-tuning"
exit ${FAILED}
