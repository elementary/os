#!/bin/bash

CONFIG_FILE="$1"

source "$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y live-build patch ubuntu-keyring

# TODO: Remove once live-build is able to acommodate for cases where LB_INITRAMFS is not live-boot:
# https://salsa.debian.org/live-team/live-build/merge_requests/31
patch -d /usr/lib/live/build/ < live-build-fix-syslinux.patch

# TODO: Remove this once debootstrap 1.0.117 or newer is released and available:
# https://salsa.debian.org/installer-team/debootstrap/blob/master/debian/changelog
ln -sfn /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/focal

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"

./terraform.sh --config-path "$CONFIG_FILE"
cp builds/amd64/* /artifacts/
