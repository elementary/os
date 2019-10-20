#!/bin/bash

set -e

CONFIG_PATH="etc/terraform.conf"

# Call getopt to validate the provided input.
options=$(getopt -o '' -l 'config-path:' -- "$@")
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}
eval set -- "$options"
while true; do
    case "$1" in
    --config-path)
        shift; # The arg is next in position args
        CONFIG_PATH=$1
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done

check_permissions () {
    if [[ "$(id -u)" != 0 ]]; then
        echo "E: Requires root permissions" > /dev/stderr
        exit 1
    fi
}


check_dependencies () {
    PACKAGES="live-build"
    for PACKAGE in $PACKAGES; do
        dpkg -L "$PACKAGE" >/dev/null 2>&1 || MISSING_PACKAGES="$MISSING_PACKAGES $PACKAGE"
    done

    if [[ "$MISSING_PACKAGES" != "" ]]; then
        echo "E: Missing dependencies! Please install the following packages: $MISSING_PACKAGES" > /dev/stderr
        exit 1
    fi
}

read_config () {
    BASE_DIR="$PWD"
    source "$BASE_DIR"/"$CONFIG_PATH"
}

build () {
    BUILD_ARCH="$1"

    mkdir -p "$BASE_DIR/tmp/$BUILD_ARCH"
    cd "$BASE_DIR/tmp/$BUILD_ARCH" || exit

    # remove old configs and copy over new
    rm -rf config auto
    cp -r "$BASE_DIR"/etc/* .
    # Make sure conffile specified as arg has correct name
    cp -f "$BASE_DIR"/"$CONFIG_PATH" terraform.conf

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

    YYYYMMDD="$(date +%Y%m%d)"
    OUTPUT_DIR="$BASE_DIR/builds/$BUILD_ARCH"
    mkdir -p "$OUTPUT_DIR"
    FNAME="elementaryos-$VERSION-$CHANNEL.$YYYYMMDD$OUTPUT_SUFFIX"
    mv "$BASE_DIR/tmp/$BUILD_ARCH/live-image-$BUILD_ARCH.hybrid.iso" "$OUTPUT_DIR/${FNAME}.iso"

    md5sum "$OUTPUT_DIR/${FNAME}.iso" > "$OUTPUT_DIR/${FNAME}.md5.txt"
    sha256sum "$OUTPUT_DIR/${FNAME}.iso" > "$OUTPUT_DIR/${FNAME}.sha256.txt"
}

check_permissions
check_dependencies
read_config

if [[ "$ARCH" == "all" ]]; then
    build amd64
    build i386
else
    build "$ARCH"
fi
