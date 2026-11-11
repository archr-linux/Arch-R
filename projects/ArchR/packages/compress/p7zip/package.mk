# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="p7zip"
PKG_VERSION="16.02"
# 2: programs in /usr/lib/p7zip, wrappers in /usr/bin (7z from PATH failed).
PKG_REV="2"
PKG_SHA256="5eb20ac0e2944f6cb9c2d51dd6c4518941c185347d4089ea89087ffdd6e2341f"
PKG_LICENSE="GPL"
PKG_SITE="http://p7zip.sourceforge.net/"
PKG_URL="http://downloads.sourceforge.net/project/p7zip/p7zip/${PKG_VERSION}/p7zip_${PKG_VERSION}_src_all.tar.bz2"
PKG_DEPENDS_HOST="ccache:host"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="p7zip is a port of 7za.exe for POSIX systems like Unix."
PKG_TOOLCHAIN="manual"

pre_build_host() {
  rm -fr ${PKG_BUILD}/.${HOST_NAME}
  mkdir -p ${PKG_BUILD}/.${HOST_NAME}
  cp -RP ${PKG_BUILD}/* ${PKG_BUILD}/.${HOST_NAME}
}

make_host() {
  make CXX=${CXX} CC=${CC} -C ${PKG_BUILD}/.${HOST_NAME} 7za
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp ${PKG_BUILD}/.${HOST_NAME}/bin/7za ${TOOLCHAIN}/bin
}

pre_build_target() {
  rm -fr ${PKG_BUILD}/.${TARGET_NAME}
  mkdir -p ${PKG_BUILD}/.${TARGET_NAME}
  cp -RP ${PKG_BUILD}/* ${PKG_BUILD}/.${TARGET_NAME}
}

make_target() {
  make CXX=${CXX} CC=${CC} -C ${PKG_BUILD}/.${TARGET_NAME} all3
}

makeinstall_target() {
  # 7z loads 7z.so and Codecs/ from the folder of argv[0]: run as "7z"
  # from PATH that is the current folder, and every archive failed with
  # "cannot find the code that works with archives". The programs live in
  # /usr/lib/p7zip, as on Arch, and /usr/bin has wrappers by full path.
  mkdir -p ${INSTALL}/usr/lib/p7zip ${INSTALL}/usr/bin
    cp -pr ${PKG_BUILD}/.${TARGET_NAME}/bin/Codecs ${INSTALL}/usr/lib/p7zip
    cp -p ${PKG_BUILD}/.${TARGET_NAME}/bin/7z* ${INSTALL}/usr/lib/p7zip
  for prog in 7z 7za 7zr; do
    [ -f ${INSTALL}/usr/lib/p7zip/${prog} ] || continue
    printf '#!/bin/sh\nexec /usr/lib/p7zip/%s "$@"\n' ${prog} >${INSTALL}/usr/bin/${prog}
    chmod 0755 ${INSTALL}/usr/bin/${prog}
  done
}
