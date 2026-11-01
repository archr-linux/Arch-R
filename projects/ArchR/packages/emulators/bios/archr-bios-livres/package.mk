# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ArchR (https://github.com/archr-linux/Arch-R)

# Free replacement BIOS only: never a manufacturer's image. Each file keeps
# its license next to it. Settings > Games > BIOS installs this package on
# demand (archr-bios-livres install) and copies a file to roms/bios only
# where nothing is there. See README.md for where each file comes from.
PKG_NAME="archr-bios-livres"
PKG_VERSION="1"
PKG_LICENSE="MIT BSD-2-Clause"
PKG_SITE="https://github.com/archr-linux/Arch-R"
# C-BIOS (MSX), official release; BSD-2-Clause.
CBIOS_VERSION="0.29a"
PKG_URL="https://downloads.sourceforge.net/project/cbios/cbios/0.29/cbios-${CBIOS_VERSION}.zip"
PKG_SHA256="c585a2f4a10b397e460a95043d59ac79cf4442fbb45a6e14a1e27ef9febaed73"
PKG_SOURCE_DIR="cbios-${CBIOS_VERSION}"
# OpenBIOS (PlayStation) from PCSX-Redux, MIT, built by build-openbios.sh.
OPENBIOS_SHA256="bc36eb489efc42a08559e50daf5d9307056fc6f31253f37b1b912ff28fb731c9"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Free BIOS replacements: OpenBIOS (PlayStation) and C-BIOS (MSX)."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  local dest=${INSTALL}/usr/share/archr/bios-livres
  mkdir -p ${dest}/cbios
  echo "${OPENBIOS_SHA256}  ${PKG_DIR}/files/openbios.bin" | sha256sum -c --quiet
  install -m 0644 ${PKG_DIR}/files/openbios.bin ${dest}/openbios.bin
  install -m 0644 ${PKG_DIR}/files/LICENSE.openbios ${dest}/LICENSE.openbios
  for rom in cbios_main_msx1 cbios_main_msx2 cbios_main_msx2+ cbios_sub; do
    install -m 0644 ${PKG_BUILD}/roms/${rom}.rom ${dest}/cbios/${rom}.rom
  done
  install -m 0644 ${PKG_DIR}/files/LICENSE.cbios ${dest}/LICENSE.cbios
}
