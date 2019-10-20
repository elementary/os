#!/bin/bash

CONFIG_FILE="$1"
KEY="$2"
SECRET="$3"
ENDPOINT="$4"
BUCKET="$5"

source "$CONFIG_FILE"

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y curl python3 python3-distutils

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
ISOPATH="$(find /artifacts -name "*.iso")"
ISO="$CHANNEL/$(basename "$ISOPATH")"
ISOTAG="$(basename "$ISOPATH" .iso)"
SHAPATH="$(find /artifacts -name "*.sha256.txt")"
SHASUM="$CHANNEL/$ISOTAG.sha256.txt"
MD5PATH="$(find /artifacts -name "*.md5.txt")"
MD5="$CHANNEL/$ISOTAG.md5.txt"

python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO"
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM"
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5"
