#!/bin/bash

#==============================================================================
# Arch R - Generate Panel DTBO Overlays
#==============================================================================
# Each MB (motherboard) variant lives under config/archr-dts/<subdevice>/<MB>/
# and ships its kernel DTB as rk3326-r36s-linux.dtb. We extract one DTBO per
# MB folder, named after the folder (spaces → underscores) so users can pick
# the exact MB instead of a generic "Panel N" that historically collided
# across distinct boards.
#
# Sources:
#   config/archr-dts/clone/<MB>/rk3326-r36s-linux.dtb
#   config/archr-dts/original/<MB>/rk3326-r36s-linux.dtb
#   config/archr-dts/soysauce/<MB>/rk3326-r36s-linux.dtb
#
# Outputs:
#   config/mipi-generator/output/clone/<MB-sanitized>.dtbo
#   config/mipi-generator/output/original/<MB-sanitized>.dtbo
#   config/mipi-generator/output/soysauce/<MB-sanitized>.dtbo
#==============================================================================

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
DTS_ROOT="${ROOT_DIR}/config/archr-dts"
OUTPUT_BASE="${MIPI_OUT:-${ROOT_DIR}/config/mipi-generator/output}"
DTBO_TOOL="$SCRIPT_DIR/archr-dtbo.py"
INPUT_DTB_NAME="rk3326-r36s-linux.dtb"

# Subdevices to process. Order matters only for log readability.
SUBDEVICES=(original clone soysauce)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[PANEL]${NC} $1"; }
warn() { echo -e "${YELLOW}[PANEL] WARNING:${NC} $1"; }
error() { echo -e "${RED}[PANEL] ERROR:${NC} $1"; exit 1; }

command -v dtc &>/dev/null || error "dtc not found"
command -v python3 &>/dev/null || error "python3 not found"
python3 -c "import fdt" 2>/dev/null || error "Python fdt package not found. Install with: pip3 install fdt"
[ -f "$DTBO_TOOL" ] || error "archr-dtbo.py not found at: $DTBO_TOOL"

GENERATED=0
FAILED=0
SKIPPED=0

# Map "G80C-MB V1.1-20250319 Panel 8" → "G80C-MB_V1.1-20250319_Panel_8".
# Spaces are the only character that needs taming; dashes, dots and digits
# are already filename-safe.
sanitize_mb_name() {
    echo "${1// /_}"
}

generate_overlay() {
    local dtb="$1"
    local out="$2"
    local label="$3"
    local flags="$4"   # optional, e.g. "JPmm-SRs"

    local cmd=(python3 "$DTBO_TOOL" "$dtb")
    [ -n "$flags" ] && cmd+=("$flags")
    cmd+=(-o "$out")

    if "${cmd[@]}" 2>/dev/null; then
        local sz=$(stat -c%s "$out")
        log "  OK: $(basename "$out") (${sz} bytes) [$label]"
        GENERATED=$((GENERATED + 1))
    else
        warn "  archr-dtbo.py failed: $(basename "$out")"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# 6 variants per panel cover every joypad×audio override the user can pick
# from the flasher UI. Dno (skip vendor mode) is applied as a runtime string
# transform on panel_description so we don't need to multiply this set by 2.
#
# Default-joypad mapping: every R36S board we ship is K36-style except for
# the Y3506 family ("soysauce") which uses MyMini-style multi-ADC sticks.
# Our vendor DTBs are partial extracts that don't expose /adc-keys, so the
# generator can't auto-detect — we baked the choice in here per subdevice.
#
# Suffix pairs: <flag string for archr-dtbo.py> | <filename suffix>
#   ""                | ""              -> default for the subdevice
#   "JPk36"           | "_JPk36"        -> force K36 joypad
#   "JPmm"            | "_JPmm"         -> force MyMini joypad
#   "SRs"             | "_SRs"          -> force simple audio routing
#   "JPk36-SRs"       | "_JPk36_SRs"    -> K36 joypad + simple audio
#   "JPmm-SRs"        | "_JPmm_SRs"     -> MyMini joypad + simple audio
VARIANT_FLAGS_K36=(""       "JPk36"     "JPmm"     "SRs"      "JPk36-SRs"     "JPmm-SRs")
VARIANT_SUFFIX_K36=(""      "_JPk36"    "_JPmm"    "_SRs"     "_JPk36_SRs"    "_JPmm_SRs")
VARIANT_FLAGS_MM=("JPmm"    "JPk36"     "JPmm"     "JPmm-SRs" "JPk36-SRs"     "JPmm-SRs")
VARIANT_SUFFIX_MM=(""       "_JPk36"    "_JPmm"    "_SRs"     "_JPk36_SRs"    "_JPmm_SRs")

# Pick the variant flag/suffix arrays that match each subdevice's expected
# default. Names are matched literally against $sd.
default_variant_arrays() {
    case "$1" in
        soysauce)
            echo "MM"
            ;;
        *)
            echo "K36"
            ;;
    esac
}

process_subdevice() {
    local sd="$1"
    local src_dir="${DTS_ROOT}/${sd}"
    local out_dir="${OUTPUT_BASE}/${sd}"

    if [ ! -d "$src_dir" ]; then
        warn "Subdevice source dir missing: $src_dir"
        return
    fi

    mkdir -p "$out_dir"

    log ""
    log "=== ${sd} panel overlays ==="
    log "Source: $src_dir"
    log "Output: $out_dir"

    local kind="$(default_variant_arrays "$sd")"
    local -n flags_arr="VARIANT_FLAGS_${kind}"
    local -n suffix_arr="VARIANT_SUFFIX_${kind}"
    log "Default joypad: ${kind} (${flags_arr[0]:-K36})"

    local count=0
    # Sort makes output deterministic across filesystems.
    while IFS= read -r mb_dir; do
        local mb_name="$(basename "$mb_dir")"
        local input_dtb="${mb_dir}/${INPUT_DTB_NAME}"

        if [ ! -f "$input_dtb" ]; then
            warn "  ${mb_name}: missing ${INPUT_DTB_NAME}"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        local sanitized="$(sanitize_mb_name "$mb_name")"
        log "  ${mb_name}"

        local i
        for i in "${!flags_arr[@]}"; do
            local flags="${flags_arr[$i]}"
            local suffix="${suffix_arr[$i]}"
            local out_file="${out_dir}/${sanitized}${suffix}.dtbo"
            generate_overlay "$input_dtb" "$out_file" "${sd}/${mb_name}${suffix}" "$flags"
        done
        count=$((count + 1))
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d | sort)

    if [ "$count" -eq 0 ]; then
        warn "${sd}: no MB folders found"
    fi
}

mkdir -p "$OUTPUT_BASE"

for sd in "${SUBDEVICES[@]}"; do
    process_subdevice "$sd"
done

log ""
log "=== Panel Generation Complete ==="
log "Generated: ${GENERATED}  Failed: ${FAILED}  Skipped: ${SKIPPED}"

for sd in "${SUBDEVICES[@]}"; do
    out_dir="${OUTPUT_BASE}/${sd}"
    [ -d "$out_dir" ] || continue
    log ""
    log "${sd} overlays: ${out_dir}/"
    ls -1 "$out_dir"/*.dtbo 2>/dev/null | while read -r f; do
        log "  $(basename "$f") ($(stat -c%s "$f") bytes)"
    done
done
