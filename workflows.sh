#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

CHANNEL="$1"
VERSION="$2"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

add-apt-repository -u -y ppa:elementary-os/os-patches
add-apt-repository -u -y ppa:elementary-os/"$CHANNEL"
apt-get install -y elementary-os-overlay
apt-get -qq update
apt-get -q -y dist-upgrade
bash -c 'echo "deb http://packages.elementary.io/appcenter $(lsb_release -sc) main" >> /etc/apt/sources.list.d/appcenter.list'
wget -q --show-progress --progress=bar:force:noscroll  2>&1 -O /etc/apt/trusted.gpg.d/appcenter.asc http://packages.elementary.io/key.asc
apt-get -q -y install --no-install-recommends \
    elementary-sdk \
    sudo \
    git \
    devscripts \
    debhelper \
    dctrl-tools \
    dpkg-dev \
    genisoimage \
    gfxboot-theme-ubuntu \
    isolinux \
    live-build \
    squashfs-tools \
    syslinux \
    syslinux-utils

# manually build this for now, until it's builds are automated.
git clone --depth=1 https://github.com/elementary/syslinux-theme.git && (cd syslinux-theme || exit 1)
debuild -us -uc -b
dpkg-deb -b debian/syslinux-themes-elementary-juno
dpkg -i debian/syslinux-themes-elementary-juno.deb

sed -i "s/CHANNEL=\"stable\"/CHANNEL=\"$CHANNEL\"/" ./etc/terraform.conf
sed -i "s/VERSION=\"5.0\"/VERSION=\"$VERSION\"/" ./etc/terraform.conf

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"
sudo bash ./terraform.sh
