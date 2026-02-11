#!/bin/bash

set -e

CONFIG_FILE="$1"
KEY="$2"
SECRET="$3"
ENDPOINT="$4"
BUCKET="$5"

source "$CONFIG_FILE"

BASEDIR="$CHANNEL"
if [ "$ARCH" != "amd64" ]; then
  BASEDIR="$CHANNEL-$ARCH"
fi

echo -e "
#----------------------#
# INSTALL DEPENDENCIES #
#----------------------#
"

apt-get update
apt-get install -y python3 python3-boto3

echo -e "
#------------#
# UPLOAD ISO #
#------------#
"

# get the paths & filenames of the files to upload
ISOPATHS="$(find builds -name "*.iso")"
while IFS= read -r ISOPATH; do
  SHAPATH="${ISOPATH%.*}.sha256.txt"
  MD5PATH="${ISOPATH%.*}.md5.txt"
  ISO="$BASEDIR/$(basename "$ISOPATH")"
  SHASUM="$BASEDIR/$(basename "$SHAPATH")"
  MD5="$BASEDIR/$(basename "$MD5PATH")"
  echo "uploading $ISO..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH" "$ISO" || exit 1
  echo "uploading $SHASUM..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$SHAPATH" "$SHASUM" || exit 1
  echo "uploading $MD5..."
  python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$MD5PATH" "$MD5" || exit 1

  if [ "$CHANNEL" == "stable" ]; then
    # install transmission
    apt-get install -y transmission-cli
    cd "$(dirname "$ISOPATH")" || exit 1
    # create torrent file
    transmission-create "$(basename "$ISOPATH")" \
      -t https://ashrise.com:443/phoenix/announce \
      -t udp://open.demonii.com:1337/announce \
      -t udp://tracker.ccc.de:80/announce \
      -t udp://tracker.istole.it:80/announce \
      -t udp://tracker.openbittorrent.com:80/announce \
      -t udp://tracker.publicbt.com:80/announce
    cd ~- || exit 1
    echo "uploading $ISO.torrent..."
    python3 upload.py "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET" "$ISOPATH.torrent" "$ISO.torrent" || exit 1

  fi
done <<< "$ISOPATHS"
