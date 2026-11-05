#!/usr/bin/env bash
# Builds sources/panel-generic-dsi.c in userspace against tests/kstub and
# runs tests/harness.c, then loads the panel_description of every in-tree
# DTS that has one.
#
#   tests/run.sh                    test sources/panel-generic-dsi.c
#   tests/run.sh path/to/driver.c   test another copy (e.g. an older one)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(dirname "$HERE")"
REPO="$(cd "$PKG/../../../../.." && pwd)"
DRIVER="$(realpath "${1:-$PKG/sources/panel-generic-dsi.c}")"
DTS_DIR="${DTS_DIR:-$REPO/projects/ArchR/devices/RK3326/linux/dts/rockchip}"
CC="${CC:-cc}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$CC" -std=gnu11 -g -O1 -Wall -Wno-pointer-sign -Wno-unused-function \
  -Wno-unused-variable -Wno-format -Wno-declaration-after-statement \
  -fsanitize=address,undefined -fno-sanitize-recover=undefined \
  -I "$HERE/kstub" -DDRIVER_SRC="\"$DRIVER\"" \
  "$HERE/harness.c" -o "$WORK/harness"

export ASAN_OPTIONS=detect_leaks=0
status=0
"$WORK/harness" || status=1

# In-tree panel descriptions must keep loading.
for dts in "$DTS_DIR"/*.dts; do
  grep -q panel_description "$dts" || continue
  python3 - "$dts" > "$WORK/lines" <<'EOF'
import re, sys
text = open(sys.argv[1]).read()
block = text[text.index('panel_description'):]
block = block[:block.index(';')]
block = '\n'.join(l for l in block.splitlines() if not l.strip().startswith('//'))
for s in re.findall(r'"([^"]*)"', block):
    print(s)
EOF
  if out="$("$WORK/harness" lines "$WORK/lines")"; then
    echo "PASS $(basename "$dts"): $out"
  else
    echo "FAIL $(basename "$dts"):"
    printf '  %s\n' "${out//$'\n'/$'\n'  }"
    status=1
  fi
done

exit "$status"
