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

patch -d /usr/lib/live/build/ < live-build-fix-syslinux.patch

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"

./terraform.sh --config-path "$CONFIG_FILE"
cp builds/amd64/* /artifacts/
