#!/bin/bash
set -e

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
cd "$OUTPUT_DIR"
md5sum "${FNAME}.iso" > "${FNAME}.md5.txt"
sha256sum "${FNAME}.iso" > "${FNAME}.sha256.txt"
cd "$BASE_DIR"