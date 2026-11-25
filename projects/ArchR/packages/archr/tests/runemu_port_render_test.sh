#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# port_render_driver: ports on libmali get SDL's GLES2 renderer.
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(dirname "${HERE}")/sources/scripts/runemu.sh"
FAILED=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got '$2', expected '$3')"; FAILED=1; fi; }
eval "$(sed -n '/^function port_render_driver() {/,/^}/p' "${SCRIPT}")"
T=$(mktemp -d)
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/mali"
run() { ( MALI_MODULE=$1; unset SDL_RENDER_DRIVER; [ -n "$2" ] && export SDL_RENDER_DRIVER=$2; port_render_driver; echo "${SDL_RENDER_DRIVER}" ); }
check "libmali: GLES2 renderer" "$(run "${T}/mali")" "opengles2"
check "libmali: a chosen renderer stays" "$(run "${T}/mali" software)" "software"
check "Mesa (no mali_kbase): untouched" "$(run "${T}/none")" ""
exit "${FAILED}"
