#!/bin/bash
set -e

# check for root permissions
if [[ "$(id -u)" != 0 ]]; then
  echo "E: Requires root permissions" > /dev/stderr
  exit 1
fi

export DEBIAN_FRONTEND="noninteractive"

# get config
if [ -n "$1" ]; then
  CONFIG_FILE="$1"
else
  CONFIG_FILE="etc/terraform.conf"
fi
BASE_DIR="$PWD"
# shellcheck disable=SC1090
source "$BASE_DIR"/"$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update

if [ "$ARCH" == "amd64" ]; then
  apt-get install -y live-build patch ubuntu-keyring

  # TODO: Remove once live-build is able to acommodate for cases where LB_INITRAMFS is not live-boot:
  # https://salsa.debian.org/live-team/live-build/merge_requests/31
  patch -d /usr/lib/live/build/ < live-build-fix-syslinux.patch
elif [ "$ARCH" == "arm64" ]; then
  apt-get install -y --no-install-recommends ca-certificates debootstrap git qemu-user-static qemu-utils qemu-system-arm binfmt-support parted kpartx rsync xz-utils curl patch
  if [ "$OEM" == "rpi" ]; then
    apt-get install -y --no-install-recommends ubuntu-keyring dosfstools
  elif [ "$OEM" == "pinebookpro" ]; then
    apt-get install -y --no-install-recommends python3 bzip2 gcc-arm-none-eabi crossbuild-essential-arm64 make bison flex bc device-tree-compiler sed build-essential libssl-dev coreutils util-linux
  else
    echo "Unsupported arm64 OEM. Backing out..." && exit 1
  fi
fi

# TODO: Remove this once debootstrap 1.0.117 or newer is released and available:
# https://salsa.debian.org/installer-team/debootstrap/blob/master/debian/changelog
ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/focal

# remove old builds & tmp before creating new ones
rm -rf "$BASE_DIR"/builds "$BASE_DIR"/tmp

mkdir -p "$BASE_DIR/tmp/$ARCH"
cd "$BASE_DIR/tmp/$ARCH" || exit
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

# start building
if [ "$ARCH" == "amd64" ]; then
  bash "$BASE_DIR"/build-amd64.sh
elif [ "$ARCH" == "arm64" ]; then
  bash "$BASE_DIR"/build-arm64.sh
fi
