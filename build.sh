#!/bin/bash

set -e

# check for root permissions
if [[ "$(id -u)" != 0 ]]; then
  echo "E: Requires root permissions" > /dev/stderr
  exit 1
fi

# get config
if [ -n "$1" ]; then
  CONFIG_FILE="$1"
else
  CONFIG_FILE="etc/terraform.conf"
fi
BASE_DIR="$PWD"
source "$BASE_DIR"/"$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y live-build patch gnupg2 binutils zstd

# The Debian repositories don't seem to have the `ubuntu-keyring` or `ubuntu-archive-keyring` packages
# anymore, so we add the archive keys manually. This may need to be updated if Ubuntu changes their signing keys
# To get the current key ID, find `ubuntu-keyring-xxxx-archive.gpg` in /etc/apt/trusted.gpg.d on a running
# system and run `gpg --keyring /etc/apt/trusted.gpg.d/ubuntu-keyring-xxxx-archive.gpg --list-public-keys `
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com F6ECB3762474EDA9D21B7022871920D1991BC93C

# TODO: This patch was submitted upstream at:
# https://salsa.debian.org/live-team/live-build/-/merge_requests/255
# This can be removed when our Debian container has a version containing this fix
patch -d /usr/lib/live/build/ < live-build-fix-shim-remove.patch

# TODO: This can be removed when our Debian container has debootstrap 1.0.124 or later
# It's needed to support the new zstd .deb package compression that Ubuntu is doing
patch -d /usr/share/debootstrap/ < debootstrap-backport-zstd-support.patch

# TODO: Remove this once debootstrap has a script to build jammy images in our container:
# https://salsa.debian.org/installer-team/debootstrap/blob/master/debian/changelog
ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/jammy

build () {
  BUILD_ARCH="$1"

  mkdir -p "$BASE_DIR/tmp/$BUILD_ARCH"
  cd "$BASE_DIR/tmp/$BUILD_ARCH" || exit

  # remove old configs and copy over new
  rm -rf config auto
  cp -r "$BASE_DIR"/etc/* .
  # Make sure conffile specified as arg has correct name
  cp -f "$BASE_DIR"/"$CONFIG_FILE" terraform.conf

  # Symlink chosen package lists to where live-build will find them
  ln -s "package-lists.$PACKAGE_LISTS_SUFFIX" "config/package-lists"

  # copy appcenter list & key
  if [ "$INCLUDE_APPCENTER" = "yes" ]; then
    cp "config/appcenter/appcenter.list.binary" "config/archives/appcenter.list.binary"
    cp "config/appcenter/appcenter.key.binary" "config/archives/appcenter.key.binary"
  fi

  echo -e "
#------------------#
# LIVE-BUILD CLEAN #
#------------------#
"
  lb clean

  echo -e "
#-------------------#
# LIVE-BUILD CONFIG #
#-------------------#
"
  lb config

  echo -e "
#------------------#
# LIVE-BUILD BUILD #
#------------------#
"
  lb build

  echo -e "
#---------------------------#
# MOVE OUTPUT TO BUILDS DIR #
#---------------------------#
"

  YYYYMMDD="$(date +%Y%m%d)"
  OUTPUT_DIR="$BASE_DIR/builds/$BUILD_ARCH"
  mkdir -p "$OUTPUT_DIR"
  FNAME="elementaryos-$VERSION-$CHANNEL.$YYYYMMDD$OUTPUT_SUFFIX"
  mv "$BASE_DIR/tmp/$BUILD_ARCH/live-image-$BUILD_ARCH.hybrid.iso" "$OUTPUT_DIR/${FNAME}.iso"

  # cd into output to so {FNAME}.sha256.txt only
  # includes the filename and not the path to
  # our file.
  cd $OUTPUT_DIR
  md5sum "${FNAME}.iso" | tee "${FNAME}.md5.txt"
  sha256sum "${FNAME}.iso" | tee "${FNAME}.sha256.txt"
  cd $BASE_DIR
}

# remove old builds before creating new ones
rm -rf "$BASE_DIR"/builds

if [[ "$ARCH" == "all" ]]; then
    build amd64
    build i386
else
    build "$ARCH"
fi
