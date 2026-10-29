# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2024-present Arch R

PKG_NAME="archr"
# archr is a local meta package with no upstream, so it carried an empty
# PKG_VERSION. That made the install_pkg dir "archr-" and gen-pacman-repo
# synthesize the constant version "archr.", so the package version never
# changed and pacman never saw an update for it (the main system config
# package). Stamp it with the build DAY so changes to system.cfg, runemu,
# wifictl, governors etc. ship as real `pacman -Syu` updates.
#
# Day resolution on purpose: the build system re-evaluates package.mk on
# every step and derives PKG_INSTALL from PKG_NAME-PKG_VERSION, so a
# seconds-resolution stamp gave the build and install steps different
# versions; the install silently skipped a PKG_INSTALL dir that did not
# exist and the image assembly then failed in post_install.
PKG_VERSION="$(date +%Y%m%d)"
PKG_LICENSE="GPLv2"
PKG_SITE=""
PKG_URL=""
# drm_tool: 055-hdmi-check and paneladj (it used to come with emulationstation).
PKG_DEPENDS_TARGET="toolchain autostart drm_tool"
PKG_LONGDESC="Arch R Meta Package"
PKG_TOOLCHAIN="make"

make_target() {
  :
}

makeinstall_target() {

  mkdir -p ${INSTALL}/usr/config/
  rsync -av ${PKG_DIR}/config/* ${INSTALL}/usr/config/

  ### es_input.cfg stays where ArchR scripts read it; emulator and core
  ### options are read-only data for the launcher.
  mkdir -p ${INSTALL}/usr/share/archr
  mv ${INSTALL}/usr/config/emulationstation/es_features.cfg ${INSTALL}/usr/share/archr/es_features.cfg
  ### Without Vulkan, drop the Vulkan options.
  if [ ! "${VULKAN_SUPPORT}" = "yes" ]
  then
    sed -i '/vulkan/d' ${INSTALL}/usr/share/archr/es_features.cfg
  fi
  ### Vertical arcade games, for vertical-check.
  install -Dm644 ${PKG_DIR}/sources/arcaderoms.xml ${INSTALL}/usr/share/archr/arcaderoms.xml
  ln -sf /storage/.config/system ${INSTALL}/system
  find ${INSTALL}/usr/config/system/ -type f -exec chmod o+x {} \;

  mkdir -p ${INSTALL}/usr/bin/

  ### Without emulation (virtual/emulators not built) the UI still needs a
  ### systems catalog: just the tools.
  if [ "${EMULATION_DEVICE}" = "no" ] || [ "${BASE_ONLY}" = "true" ]
  then
    mkdir -p ${INSTALL}/usr/share/archr
    cat <<EOF >${INSTALL}/usr/share/archr/systems.cfg
<?xml version="1.0" encoding="UTF-8"?>
<systemList>
        <system>
                <name>tools</name>
                <fullname>Tools</fullname>
                <manufacturer>ArchR</manufacturer>
                <release>2024</release>
                <hardware>system</hardware>
                <path>/storage/.config/modules</path>
                <extension>.sh</extension>
                <command>%ROM%</command>
                <platform>tools</platform>
                <theme>tools</theme>
        </system>
</systemList>
EOF
  fi

  ### Pre-generate the default locale (en_US.UTF-8): generating it on the
  ### device takes a minute or two on RK3326, for about 1 MB here.
  ### userconfig-setup copies it to /storage/.config/locale, where
  ### archr-apply-locale generates any other language.
  mkdir -p ${INSTALL}/usr/config/locale
  I18NPATH=$(get_install_dir glibc)/usr/share/i18n/locales/ \
    localedef --force --verbose --inputfile=en_US --charmap=UTF-8 \
    ${INSTALL}/usr/config/locale/en_US.UTF-8 || true

  ### archr-apply-locale writes the zone here.
  mkdir -p ${INSTALL}/etc
  ln -sf /storage/.cache/system_timezone ${INSTALL}/etc/timezone

  ### Compatibility links for ports
  ln -s /storage/roms ${INSTALL}/roms

  ### Add some quality of life customizations for hardworking devs.
  if [ -n "${LOCAL_SSH_KEYS_FILE}" ]
  then
    mkdir -p ${INSTALL}/usr/config/ssh
    cp ${LOCAL_SSH_KEYS_FILE} ${INSTALL}/usr/config/ssh/authorized_keys
  fi

  if [ -n "${LOCAL_WIFI_SSID}" ]
  then
    sed -i "s#wifi.enabled=0#wifi.enabled=1#g" ${INSTALL}/usr/config/system/configs/system.cfg
    mkdir -p ${INSTALL}/usr/config/iwd
    cat <<EOF >> ${INSTALL}/usr/config/iwd/${LOCAL_WIFI_SSID}.psk
[Security]
Passphrase=${LOCAL_WIFI_KEY}
EOF
  fi
  # Always install the update script
  mkdir -p $INSTALL/usr/share/bootloader
  find_file_path bootloader/update.sh && cp -av ${FOUND_PATH} ${INSTALL}/usr/share/bootloader

  ### FHS bridge symlinks: make Arch-standard cache locations resolve into
  ### the /storage overlay. Apps and inspection tools see /var/cache/<x>;
  ### writes land in /storage/.cache/<x> (rw overlay).
  mkdir -p ${INSTALL}/var/cache/archr
  ln -sf /storage/.cache/mesa_shader_cache ${INSTALL}/var/cache/mesa
  ln -sf /storage/.cache/kernel-overlays   ${INSTALL}/var/cache/archr/kernel-overlays
  ln -sf /storage/.cache/locpath           ${INSTALL}/var/cache/archr/locpath
  # fstrim.run is a stamp file, not a directory; the symlink resolves
  # both `touch /var/cache/archr/fstrim.run` (writes through) and
  # readers checking the stamp.
  ln -sf /storage/.cache/fstrim.run        ${INSTALL}/var/cache/archr/fstrim.run
  # Image-based updates: backing path /storage/.update is what the
  # pre-boot bootloader scripts know about and cannot move; userland
  # tooling reads/writes through the FHS bridge.
  ln -sf /storage/.update                  ${INSTALL}/var/cache/archr/update

  # State directories for runtime data the system writes back to the
  # storage overlay. Same bridge pattern, just under /var/lib instead
  # of /var/cache.
  mkdir -p ${INSTALL}/var/lib/archr
  ln -sf /storage/.cache/services          ${INSTALL}/var/lib/archr/services
  # samba passdb at the Arch-standard /var/lib/samba/private path.
  mkdir -p ${INSTALL}/var/lib/samba
  ln -sf /storage/.cache/samba             ${INSTALL}/var/lib/samba/private
  # tailscale daemon state (Arch convention).
  ln -sf /storage/.cache/tailscale         ${INSTALL}/var/lib/tailscale
  # cron spool (Arch convention; busybox crond walks the subtree).
  mkdir -p ${INSTALL}/var/spool
  ln -sf /storage/.cache/cron              ${INSTALL}/var/spool/cron

  # Class B umbrella bridges. Emulator and app configs continue to live
  # in /storage/.config/<emu> and /storage/.local/share/<emu> on disk;
  # these bridges give them Arch-friendly surface paths so inspection
  # tools, the ARCHR_CONFIG / ARCHR_DATA variables and migrated scripts
  # all resolve into the same overlay storage. Per-emulator scripts can
  # be flipped to /var/lib/archr/config/<emu> incrementally without
  # this bridge having to change.
  ln -sf /storage/.config                  ${INSTALL}/var/lib/archr/config
  mkdir -p ${INSTALL}/var/lib/archr
  ln -sf /storage/.local/share             ${INSTALL}/var/lib/archr/data

  # Class E umbrella bridge. Games library has the largest surface in
  # the codebase (117 files in projects/ArchR reference /storage/roms),
  # same pattern as Class B: the rw overlay address stays /storage/roms,
  # the Arch-friendly address /var/lib/archr/games is a symlink so
  # ARCHR_GAMES and inspection tools see the FHS path. Per-script
  # refactors can happen organically.
  ln -sf /storage/roms                     ${INSTALL}/var/lib/archr/games
  ln -sf /storage/backup                   ${INSTALL}/var/lib/archr/backup

  # Class Z odd corners. Each path has a different reason but the same
  # idea: surface lives at the FHS address, substrate stays on the
  # overlay so existing data persists.
  #
  # Only paths without an umbrella in scope need an explicit bridge.
  # hatari and openbor fall through the data/games umbrellas already:
  # /var/lib/archr/data/hatari resolves to /storage/.local/share/hatari
  # at runtime via the data symlink; same for games/openbor. The
  # start_hatari.sh and start_OpenBOR.sh scripts already mkdir -p the
  # final dir so it materializes on first launch.
  mkdir -p ${INSTALL}/opt
  ln -sf /storage/jdk                      ${INSTALL}/opt/jdk

  # Scripts and alpm hooks belong in makeinstall_target, NOT post_install:
  # post_install writes straight into the assembled image, so anything
  # done there never lands in the pacman package and stays flash-only.
  # These (archr-update, flash-sync, the depmod hook, wifictl, ...) must
  # reach users through `pacman -Syu` too, so they go here.
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/scripts/* ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/* 2>/dev/null ||:
  mkdir -p ${INSTALL}/etc/pacman.d/hooks
  cp ${PKG_DIR}/sources/pacman-hooks/*.hook ${INSTALL}/etc/pacman.d/hooks
}

post_install() {
  ln -sf archr.target ${INSTALL}/usr/lib/systemd/system/default.target

  ### Locales live on /storage (generated on the device for the chosen
  ### language); glibc's default lookup, /usr/lib/locale, reaches them.
  ### Image-only links, like before: pacman never owned them.
  mkdir -p ${INSTALL}/usr/share ${INSTALL}/usr/lib
  ln -sf /storage/.config/locale ${INSTALL}/usr/share/locale
  ln -sf /usr/share/locale ${INSTALL}/usr/lib/locale

  if [ ! -d "${INSTALL}/usr/share" ]
  then
    mkdir "${INSTALL}/usr/share"
  fi
  cp ${PKG_DIR}/sources/post-update ${INSTALL}/usr/share
  chmod 755 ${INSTALL}/usr/share/post-update

  # Issue banner (no ASCII art - archr-splash handles the graphical logo)
  cat <<EOF >> ${INSTALL}/etc/issue

... Version: ${OS_VERSION} (${OS_BUILD})
... Built: ${BUILD_DATE}

EOF
  cp ${PKG_DIR}/sources/motd ${INSTALL}/etc
  cat ${INSTALL}/etc/issue >> ${INSTALL}/etc/motd

  ### Install man pages
  if [ -d "${PKG_DIR}/sources/man" ]; then
    for page in ${PKG_DIR}/sources/man/*.[1-9]; do
      [ -f "${page}" ] || continue
      section=${page##*.}
      mkdir -p ${INSTALL}/usr/share/man/man${section}
      cp ${page} ${INSTALL}/usr/share/man/man${section}/
    done
  fi

  ### Fix and migrate to autostart package
  enable_service archr-autostart.service

  ### ZRAM/Swap and Memory Manager Service
  enable_service archr-memory-manager.service

  ### Take a backup of the system configuration on shutdown
  enable_service save-sysconfig.service

  ### Expose PortMaster compat libs (/usr/lib/compat) in the default
  ### linker path. No ld.so.cache ships, so love_11.5 et al. fail on
  ### libtheoradec.so.1 unless it is symlinked into /usr/lib (see
  ### docs/PortMaster_CFW.md and the archr-compat-symlinks script).
  enable_service archr-compat-libs.service

  ### System locale. glibc/package.mk only generates en_US.UTF-8; without
  ### this file LANG stays empty and every shell falls back to POSIX,
  ### which breaks UTF-8 input, pacman messages and emulator menus.
  echo "LANG=en_US.UTF-8" > ${INSTALL}/etc/locale.conf

  sed -i "s#@DEVICENAME@#${DEVICE}#g" ${INSTALL}/usr/config/system/configs/system.cfg

  ### Defaults for non-main builds.
  BUILD_BRANCH="$(git branch --show-current)"
  if [ ! "${BUILD_BRANCH}" = "main" ]
  then
    sed -i "s#samba.enabled=0#samba.enabled=1#g" ${INSTALL}/usr/config/system/configs/system.cfg
    sed -i "s#ssh.enabled=0#ssh.enabled=1#g" ${INSTALL}/usr/config/system/configs/system.cfg
    sed -i "s#wifi.enabled=0#wifi.enabled=1#g" ${INSTALL}/usr/config/system/configs/system.cfg
    sed -i "s#system.loglevel=none#system.loglevel=verbose#g" ${INSTALL}/usr/config/system/configs/system.cfg
  fi

}
