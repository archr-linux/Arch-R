# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026 Arch R (https://github.com/archr-linux)

PKG_NAME="coreutils"
PKG_VERSION="9.6"
PKG_SHA256="7a0124327b398fd9eb1a6abde583389821422c744ffa10734b24f557610d3283"
PKG_LICENSE="GPLv2+"
PKG_SITE="https://www.gnu.org/software/coreutils/"
PKG_URL="https://mirrors.kernel.org/gnu/coreutils/coreutils-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="The GNU Core Utilities are the basic file, shell and text manipulation utilities of the GNU operating system."
PKG_TOOLCHAIN="auto"

PKG_CONFIGURE_OPTS_TARGET="--disable-nls \
                           --without-gmp \
                           --without-selinux \
                           --enable-no-install-program=kill,uptime,groups"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin

  # Install all GNU coreutils binaries replacing BusyBox equivalents
  local COREUTILS_BINS="
    base32 base64 basename cat chcon chgrp chmod chown chroot cksum comm
    cp csplit cut date dd df dir dircolors dirname du echo env expand
    expr factor false fmt fold head hostid id install join link ln
    logname ls md5sum mkdir mkfifo mknod mktemp mv nice nl nohup
    nproc numfmt od paste pathchk pinky pr printenv printf ptx pwd
    readlink realpath rm rmdir runcon seq sha1sum sha224sum sha256sum
    sha384sum sha512sum shred shuf sleep sort split stat stdbuf stty
    sum sync tac tail tee test timeout touch tr true truncate tsort
    tty uname unexpand uniq unlink users vdir wc who whoami yes
  "

  for bin in ${COREUTILS_BINS}; do
    if [ -f ${PKG_BUILD}/.${TARGET_NAME}/src/${bin} ]; then
      cp ${PKG_BUILD}/.${TARGET_NAME}/src/${bin} ${INSTALL}/usr/bin/
    fi
  done

  # Install libstdbuf
  mkdir -p ${INSTALL}/usr/lib/coreutils
  if [ -f ${PKG_BUILD}/.${TARGET_NAME}/src/libstdbuf.so ]; then
    cp ${PKG_BUILD}/.${TARGET_NAME}/src/libstdbuf.so ${INSTALL}/usr/lib/coreutils/
  fi

  # Create compatibility symlink: [ -> test
  ln -sf test ${INSTALL}/usr/bin/[
}
