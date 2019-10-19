#!/bin/bash

CONFIG_FILE="$1"
KEY="$2"
SECRET="$3"
ENDPOINT="$4"
BUCKET="$5"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y live-build patch curl python3 python3-distutils

patch -d /usr/lib/live/build/ < live-build-fix-syslinux.patch

echo -e "
#----------------------#
# RUN TERRAFORM SCRIPT #
#----------------------#
"

./terraform.sh --config-path "$CONFIG_FILE"
cp builds/amd64/* /artifacts/

echo -e "
#------------#
# UPLOAD ISO #
#------------#
"
# install boto, which can  be fetched via pip
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
pip install boto3

# get the paths & filenames of the files to upload
ISOPATH="$(find builds -name "*.iso")"
ISO="$CHANNEL/$(basename "$ISOPATH")"
ISOTAG="$(basename "$ISOPATH" .iso)"
SHAPATH="$(find builds -name "*.sha256.txt")"
SHASUM="$CHANNEL/$ISOTAG.sha256.txt"
MD5PATH="$(find builds -name "*.md5.txt")"
MD5="$CHANNEL/$ISOTAG.md5.txt"

python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO"
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM"
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5"
