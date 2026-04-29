# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="gamesupport"
PKG_LICENSE="GPLv2"
PKG_SITE="https://arch-r.io"
PKG_SECTION="virtual"
PKG_LONGDESC="Game support software metapackage."

PKG_GAMESUPPORT="sixaxis archr-hotkey jstest-sdl gamecontrollerdb sdljoytest sdltouchtest control-gen sdl2text"

case ${DEVICE} in
  SM8250|SM8550|SM8650|SDM845|S922X|RK3326)
    PKG_GAMESUPPORT+=" mangohud"
  ;;
esac

# archr-touchscreen-keyboard requires sway
[[ "${WINDOWMANAGER}" = "swaywm-env" ]] && PKG_GAMESUPPORT+=" archr-touchscreen-keyboard"

PKG_DEPENDS_TARGET="${PKG_GAMESUPPORT}"

