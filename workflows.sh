#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

CHANNEL="$1"
VERSION="$2"
KEY="$3"
SECRET="$4"
ENDPOINT="$5"
BUCKET="$6"

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
    syslinux-utils \
    syslinux-common

# manually build this for now, until it's builds are automated.
git clone --depth=1 https://github.com/elementary/syslinux-theme.git && cd syslinux-theme || exit 1
debuild -us -uc -b
dpkg-deb -b debian/syslinux-themes-elementary-juno
dpkg -i debian/syslinux-themes-elementary-juno.deb
cd .. || exit 1

sed -i "s/CHANNEL=\"stable\"/CHANNEL=\"$CHANNEL\"/" ./etc/terraform.conf
sed -i "s/VERSION=\"5.0\"/VERSION=\"$VERSION\"/" ./etc/terraform.conf

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"
sudo bash ./terraform.sh

echo -e "
#------------#
# UPLOAD ISO #
#------------#
"
# install boto, which can  be fetched via pip
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py
pip install boto3

# get the paths & filenames of the files to upload
ISOPATH="$(find builds -name "*.iso")"
ISO="$CHANNEL/$(basename "$ISOPATH")"
ISOTAG="$(basename "$ISOPATH" .iso)"
SHAPATH="$(find builds -name "*.sha256.txt")"
SHASUM="$CHANNEL/$ISOTAG.sha256.txt"
MD5PATH="$(find builds -name "*.md5.txt")"
MD5="$CHANNEL/$ISOTAG.md5.txt"

python upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO"
python upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM"
python upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5"


