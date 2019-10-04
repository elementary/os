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

# get the paths & filenames of the files to upload
ISOPATH="$(find builds -name "*.iso")"
ISO="$(basename "$ISOPATH")"
SHAPATH="$(find builds -name "*.sha256.txt")"
SHASUM="$(basename "$SHAPATH")"
MD5PATH="$(find builds -name "*.md5.txt")"
MD5="$(basename "$MD5PATH")"

upload () {
  # set date and content type for related headers
  DATE="$(date -R)"
  CONTENT_TYPE="$3"
  # Create signature for upload
  stringToSign="PUT\n\n${CONTENT_TYPE}\n${DATE}\n/${{ secrets.bucket }}/$1"
  signature="$(echo -en "${stringToSign}" | openssl sha1 -hmac "${{ secrets.secret }}" -binary | base64)"
  curl -D- -X PUT -T "$1" \
    -H "Host: ${{ secrets.bucket }}.${{ secrets.endpoint }}" \
    -H "Date: ${DATE}" \
    -H "Content-Type: ${CONTENT_TYPE}" \
    -H "Authorization: AWS ${{ secrets.key }}:${signature}" \
    -L "http://${{ secrets.bucket }}.${{ secrest.endpoint }}/$2" --post301
}

upload "$ISOPATH" "$ISO" "application/octet-stream"
upload "$SHAPATH" "$SHASUM" "text/plain"
upload "$MD5PATH" "$MD5" "text/plain"


