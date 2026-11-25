#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# archr-boot-tuning against a scratch root: each step's range, the
# overlay's nodes (a new CPU step with its frequency and latency, a GPU
# step), a uniform CPU offset, extlinux.conf listing the overlay once, the
# neutral overlay after reset, a revert told once, and new DTBs (the
# 600 MHz table) putting the neutral overlay back.
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
# The RK3326 tables before 20261125.2: no 1200 and 1296 MHz steps, so they
# are the new ones.
python3 -I - "${TMP}" <<'PY'
import os, struct, sys
dt = sys.argv[1] + "/proc/device-tree"
cpu = [(408, 950000), (816, 1050000), (1008, 1175000), (1416, 1350000), (1512, 1400000)]
for mhz, uv in cpu:
    d = f"{dt}/opp-table-0/opp-{mhz}000000"; os.makedirs(d)
    top = 1400000 if mhz == 1512 else 1350000
    open(f"{d}/opp-microvolt", "wb").write(struct.pack(">3I", uv, uv, top))
    open(f"{d}/clock-latency-ns", "wb").write(struct.pack(">I", 40000))
for mhz, uv in [(200, 1100000), (400, 1100000), (560, 1125000), (650, 1150000)]:
    d = f"{dt}/opp-table-1/opp-{mhz}000000"; os.makedirs(d)
    open(f"{d}/opp-microvolt", "wb").write(struct.pack(">I", uv))
PY
run() { python3 -I "${TOOL}" "$@"; }
field() { python3 -I -c 'import json,sys; v=json.load(sys.stdin)
for p in sys.argv[1].split("."): v=v[int(p)] if p.isdigit() else v[p]
print(v if isinstance(v, str) else json.dumps(v, separators=(",", ":")))' "$1"; }
# The overlay's nodes, one per line: "<fragment target> <node> <prop>=<cells>".
dump() {
  python3 -I - "$1" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
off_struct, off_str = struct.unpack(">II", b[8:16])
strings = b[off_str:]
i, path, target, lines = off_struct, [], "", []
while True:
    tok = struct.unpack(">I", b[i:i+4])[0]; i += 4
    if tok == 1:
        end = b.index(b"\0", i); path.append(b[i:end].decode()); i = (end + 4) & ~3
    elif tok == 3:
        ln, no = struct.unpack(">II", b[i:i+8]); i += 8
        name = strings[no:strings.index(b"\0", no)].decode()
        val = b[i:i+ln]; i = (i + ln + 3) & ~3
        if name == "target-path":
            target = val.rstrip(b"\0").decode()
        else:
            cells = ",".join(str(v) for v in struct.unpack(">%dI" % (ln // 4), val))
            lines.append(f"{target} {path[-1]} {name}={cells}")
    elif tok == 2:
        path.pop()
    elif tok == 9:
        break
print("\n".join(lines))
PY
}
ACTIVE=${TMP}/flash/overlays/tuning.dtbo

expect "the 1416 step" "[1416,0,1350,1300,1375]" "$(run brief | field cpu.5)"
expect "1200 between 1008 and 1416" "[1200,0,0,1175,1375]" "$(run brief | field cpu.3)"
expect "the GPU: only steps over the floor" "[[560,0,1125,1100,1125],[650,0,1150,1100,1150]]" "$(run brief | field gpu)"
expect "brief fits a module's 600 bytes" "1" "$([ "$(run brief | wc -c)" -le 600 ] && echo 1)"

expect "1416 down 25" '{"ok":true,"reboot":true}' "$(run set cpu 1416 1325000)"
expect "a new 1296 step" '{"ok":true,"reboot":true}' "$(run set cpu 1296 1312500)"
expect "the GPU at 1.125 V" '{"ok":true,"reboot":true}' "$(run set gpu 650 1125000)"
expect "nodes" "/opp-table-0 opp-1296000000 opp-hz=0,1296000000
/opp-table-0 opp-1296000000 opp-microvolt=1312500,1312500,1350000
/opp-table-0 opp-1296000000 clock-latency-ns=40000
/opp-table-0 opp-1416000000 opp-microvolt=1325000,1325000,1350000
/opp-table-1 opp-650000000 opp-microvolt=1125000" "$(dump "${ACTIVE}")"
expect "chosen in brief" "[1296,1312.5,0,1175,1375]" "$(run brief | field cpu.4)"
expect "pending" "true" "$(run brief | field pending)"
expect "listed once, after the panel" "  FDTOVERLAYS /overlays/mipi-panel.dtbo /overlays/tuning.dtbo" \
  "$(grep tuning.dtbo "${TMP}/flash/extlinux/extlinux.conf")"

expect "under the step's range" "out_of_range" "$(run set cpu 1296 1162500 | field error)"
expect "off the 12.5 mV step" "out_of_range" "$(run set cpu 1416 1330000 | field error)"
expect "over 25 mV" "out_of_range" "$(run set cpu 1416 1387500 | field error)"
expect "the GPU under 1.1 V" "out_of_range" "$(run set gpu 650 1087500 | field error)"
expect "the GPU over stock" "out_of_range" "$(run set gpu 650 1162500 | field error)"
expect "a GPU step at the floor" "no_step" "$(run set gpu 400 1100000 | field error)"
expect "a CPU step that is not there" "no_step" "$(run set cpu 1100 1200000 | field error)"

# Every CPU step 25 mV down: the new 1296 from 1416's stock; 1200 stays off.
run offset cpu -25000 >/dev/null
expect "offset" "/opp-table-0 opp-408000000 opp-microvolt=925000,925000,1350000
/opp-table-0 opp-816000000 opp-microvolt=1025000,1025000,1350000
/opp-table-0 opp-1008000000 opp-microvolt=1150000,1150000,1350000
/opp-table-0 opp-1296000000 opp-hz=0,1296000000
/opp-table-0 opp-1296000000 opp-microvolt=1325000,1325000,1350000
/opp-table-0 opp-1296000000 clock-latency-ns=40000
/opp-table-0 opp-1416000000 opp-microvolt=1325000,1325000,1350000
/opp-table-0 opp-1512000000 opp-microvolt=1375000,1375000,1400000
/opp-table-1 opp-650000000 opp-microvolt=1125000" "$(dump "${ACTIVE}")"
expect "offset range" "out_of_range" "$(run offset cpu -62500 | field error)"
expect "offset step" "out_of_range" "$(run offset cpu -5000 | field error)"
# Back to stock at 0, keeping the new step at its base.
run offset cpu 0 >/dev/null
expect "offset 0" "/opp-table-0 opp-1296000000 opp-hz=0,1296000000
/opp-table-0 opp-1296000000 opp-microvolt=1350000,1350000,1350000
/opp-table-0 opp-1296000000 clock-latency-ns=40000
/opp-table-1 opp-650000000 opp-microvolt=1125000" "$(dump "${ACTIVE}")"
run set cpu 1296 0 >/dev/null
expect "a new step removed" "/opp-table-1 opp-650000000 opp-microvolt=1125000" "$(dump "${ACTIVE}")"

run reset >/dev/null
expect "neutral" "true" "$(run status | field neutral)"
expect "same as the neutral one" "1" "$(cmp -s "${ACTIVE}" "${TMP}/flash/overlays/tuning.neutral.dtbo" && echo 1)"
expect "listed once after reset" "1" "$(grep -c tuning.dtbo "${TMP}/flash/extlinux/extlinux.conf")"

# The initramfs reverted: told once, settings cleared, kept in the status.
run set cpu 1416 1300000 >/dev/null
cp "${TMP}/flash/overlays/tuning.neutral.dtbo" "${ACTIVE}"
echo 2 >"${TMP}/flash/tuning.reverted"
expect "revert told" "true" "$(run boot | field reverted)"
expect "once" "false" "$(run boot | field reverted)"
expect "one toast" "1" "$(wc -l <"${TMP}/toasts")"
expect "in English without a language" "error errors Voltage tuning undone: the console froze twice Stock voltages restored" \
  "$(cat "${TMP}/toasts")"
expect "status keeps it" "2" "$(run status | field reverted)"
expect "brief says so" "true" "$(run brief | field reverted)"
expect "settings cleared" "[1416,0,1350,1300,1375]" "$(run brief | field cpu.5)"

# New DTBs with the 600 MHz table (20261125.2): the 408 MHz node of the old
# settings would break the CPU table, so the neutral overlay goes back.
run offset cpu -25000 >/dev/null
run boot >/dev/null
: >"${TMP}/toasts"
expect "tuned before the update" "false" "$(run status | field neutral)"
expect "dtbs-changed resets" '{"ok":true,"reset":true}' "$(run dtbs-changed)"
expect "neutral after it" "1" "$(cmp -s "${ACTIVE}" "${TMP}/flash/overlays/tuning.neutral.dtbo" && echo 1)"
expect "no stock kept" "1" "$([ ! -e "${TMP}/flash/tuning.stock.json" ] && echo 1)"
expect "nothing read from the old tree" "false" "$(run brief | field supported)"
rm -rf "${TMP:?}/proc/device-tree/opp-table-0"
python3 -I - "${TMP}" <<'PY'
import os, struct, sys
dt = sys.argv[1] + "/proc/device-tree"
cpu = [(600, 950000), (816, 1050000), (1008, 1175000), (1200, 1300000), (1296, 1350000),
       (1416, 1350000), (1512, 1400000)]
for mhz, uv in cpu:
    d = f"{dt}/opp-table-0/opp-{mhz}000000"; os.makedirs(d)
    top = 1400000 if mhz == 1512 else 1350000
    open(f"{d}/opp-microvolt", "wb").write(struct.pack(">3I", uv, uv, top))
    open(f"{d}/clock-latency-ns", "wb").write(struct.pack(">I", 40000))
PY
run boot >/dev/null
expect "told at the next boot" "info updates Voltage tuning undone by the update The processor table changed; tune it again in Performance and chip" \
  "$(cat "${TMP}/toasts")"
expect "told once" "false" "$(run boot | field reset)"
expect "600 MHz first" "[600,0,950,900,975]" "$(run brief | field cpu.0)"
expect "1296 a stock step now" "[1296,0,1350,1300,1375]" "$(run brief | field cpu.4)"
expect "seven CPU steps" "7" "$(run brief | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["cpu"]))')"
expect "untouched settings: nothing to do" '{"ok":true,"reset":false}' "$(run dtbs-changed)"
[ ${FAILED} -eq 0 ] && echo "ok   archr-boot-tuning"
exit ${FAILED}
