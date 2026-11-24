# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="sleep"
PKG_VERSION="2.1"
PKG_REV="1"
PKG_LICENSE="OSS"
PKG_DEPENDS_TARGET="systemd"
PKG_SITE=""
PKG_URL=""
PKG_LONGDESC="Sleep configuration"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
	mkdir -p ${INSTALL}/usr/config/sleep.conf.d
	cp sleep.conf ${INSTALL}/usr/config/sleep.conf.d/sleep.conf
	if [ "${DEVICE}" = "RK3326" ] || [ "${DEVICE}" = "RK3562" ]; then
	  # px30 mainline has no working kernel suspend at all: "mem" hangs
	  # on entry and "freeze" (s2idle) enters but never wakes, not even
	  # from an armed RTC alarm (tested 2026-07-07 on the Soysauce with
	  # every wakeup source enabled; real debugging needs UART). Inhibit
	  # real suspend by default so the power button falls through to
	  # archr-fake-suspend; the ES SUSPEND MODE menu rewrites this file
	  # via the suspendmode script, so advanced users can still opt in
	  # to experiment. Keep freeze first for that case: it is the least
	  # bad state on this SoC.
	  # The RK3562 (linux 7.3) starts the same way until its suspend is
	  # tested.
	  sed -i 's/^AllowSuspend=.*/AllowSuspend=no/' ${INSTALL}/usr/config/sleep.conf.d/sleep.conf
	  sed -i 's/^SuspendState=.*/SuspendState=freeze/' ${INSTALL}/usr/config/sleep.conf.d/sleep.conf
	fi
        cp modules.bad ${INSTALL}/usr/config

	mkdir -p ${INSTALL}/usr/lib/systemd/system-sleep/
	cp sleep.sh ${INSTALL}/usr/lib/systemd/system-sleep/sleep
	chmod +x ${INSTALL}/usr/lib/systemd/system-sleep/sleep
}
