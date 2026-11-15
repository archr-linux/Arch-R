#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2021-present 351ELEC (https://github.com/351ELEC)

. /etc/profile

clear > /dev/console

if [ ! -f "/storage/roms/bios/freej2me-lr.jar" ]; then
    cp /usr/config/game/freej2me/freej2me-lr.jar /storage/roms/bios
fi

JDKDEST="/opt/jdk"
JDKNAME="zulu11.48.21-ca-jdk11.0.11"

# /opt/jdk -> /storage/jdk; if anything left a non-directory there the
# mkdir/tar steps below would fail with "Not a directory".
if [ -L /opt/jdk ]; then
  jdk_target=$(readlink /opt/jdk)
  if [ -e "${jdk_target}" ] && [ ! -d "${jdk_target}" ]; then
    rm -f "${jdk_target}"
  fi
fi

# The link's target (/storage/jdk) is made here: a mkdir -p of the link
# itself fails while the target is missing, the JDK then never landed and
# every launch downloaded it again.
JDKREAL=$(readlink -f "${JDKDEST}")
mkdir -p "${JDKREAL}" || exit 1

# Check if the jdk does not already exists
[ -x "${JDKREAL}/bin/java" ] && JDKINSTALLED="yes" || JDKINSTALLED="no"

if [ ${JDKINSTALLED} == "no" ]; then
  echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1
  if [ $? -ne 0 ]; then
      text_viewer -e -w -t "No Internet!" -m "You need to be connected to the internet to download the JDK.";
      exit 1
  fi
  echo "Downloading JDK please be patient..." > /dev/console
  cd "${JDKREAL}/.." || exit 1
  wget "https://cdn.azul.com/zulu-embedded/bin/${JDKNAME}-linux_aarch64.tar.gz" > /dev/console 2>&1
  echo "Inflating JDK please be patient..." > /dev/console
  tar xvfz ${JDKNAME}-linux_aarch64.tar.gz ${JDKNAME}-linux_aarch64/lib > /dev/console 2>&1
  tar xvfz ${JDKNAME}-linux_aarch64.tar.gz ${JDKNAME}-linux_aarch64/bin > /dev/console 2>&1
  tar xvfz ${JDKNAME}-linux_aarch64.tar.gz ${JDKNAME}-linux_aarch64/conf > /dev/console 2>&1
  rm ${JDKNAME}-linux_aarch64/lib/*.zip
  mv ${JDKNAME}-linux_aarch64/* "${JDKREAL}/"
  rm -rf ${JDKNAME}-linux_aarch64*

  for del in jmods include demo legal man DISCLAIMER LICENSE readme.txt release Welcome.html; do
      rm -rf "${JDKREAL:?}/${del}"
  done
  echo "JDK done! loading core!" > /dev/console
  cp -rf /usr/config/game/freej2me/freej2me-lr.jar /storage/roms/bios
fi

clear > /dev/console < /dev/null 2>&1
exit 0
