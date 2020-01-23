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
ISOPATHS="$(find builds -name "*.iso")"
while IFS= read -r ISOPATH; do
  SHAPATH="${ISOPATH%.*}.sha256.txt"
  MD5PATH="${ISOPATH%.*}.md5.txt"
  ISO="$CHANNEL/$(basename "$ISOPATH")"
  SHASUM="$CHANNEL/$(basename "$SHAPATH")"
  MD5="$CHANNEL/$(basename "$MD5PATH")"
  echo "uploading $ISO..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO" || exit 1
  echo "uploading $SHASUM..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM" || exit 1
  echo "uploading $MD5..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5" || exit 1
done <<< "$ISOPATHS"
