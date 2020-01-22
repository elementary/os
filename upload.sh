#!/bin/bash

set -e

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
ISOPATH="$(find /builds/amd64 -name "*.iso")"
ISO="$CHANNEL/$(basename "$ISOPATH")"
ISOTAG="$(basename "$ISOPATH" .iso)"
SHAPATH="$(find /builds/amd64 -name "*.sha256.txt")"
SHASUM="$CHANNEL/$ISOTAG.sha256.txt"
MD5PATH="$(find /builds/amd64 -name "*.md5.txt")"
MD5="$CHANNEL/$ISOTAG.md5.txt"

python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO" || exit 1
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM" || exit 1
python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5" || exit 1
