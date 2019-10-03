#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

CHANNEL="$1"
VERSION="$2"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get -qq update
apt-get -y install software-properties-common
add-apt-repository -u -y ppa:elementary-os/os-patches
add-apt-repository -u -y ppa:elementary-os/"$CHANNEL"
apt-get install -y elementary-os-overlay
apt-get update
apt-get -y dist-upgrade
bash -c 'echo "deb http://packages.elementary.io/appcenter $(lsb_release -sc) main" >> /etc/apt/sources.list.d/appcenter.list'
wget -q --show-progress --progress=bar:force:noscroll  2>&1 -O /etc/apt/trusted.gpg.d/appcenter.asc http://packages.elementary.io/key.asc
apt-get install --no-install-recommends -y elementary-sdk
apt-get -q -y install git devscripts debhelper dctrl-tools dpkg-dev genisoimage gfxboot-theme-ubuntu isolinux live-build squashfs-tools syslinux syslinux-utils

git clone --depth=1 https://github.com/elementary/syslinux-theme.git && cd syslinux-theme
debuild -S -sd

sed -i "s/CHANNEL=\"stable\"/CHANNEL=\"$CHANNEL\"/" etc/terraform.conf
sed -i "s/VERSION=\"5.0\"/VERSION=\"$VERSION\"/" etc/terraform.conf

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"
./terraform.sh
