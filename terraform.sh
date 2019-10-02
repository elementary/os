#!/bin/bash

set -e

check_permissions () {
    if [[ "$(id -u)" != 0 ]]; then
        echo "E: Requires root permissions" > /dev/stderr
        exit 1
    fi
}

check_dependencies () {
    PACKAGES="dctrl-tools dpkg-dev genisoimage gfxboot-theme-ubuntu isolinux live-build squashfs-tools syslinux syslinux-utils"
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
    source "$BASE_DIR"/etc/terraform.conf
}

uefi () {
    ISO="$1"

    # /tmp/tmp.XXXXXXXXXX
    TMP_DIR=$(mktemp -d)

    clean_up () {
      umount "$TMP_DIR/mnt" >/dev/null 2>&1 || true
      rm -rf "$TMP_DIR"
    }
    trap clean_up EXIT

    # Create temporary directories
    mkdir -p "$TMP_DIR"/{contents,mnt}

    # Mount .iso
    mount -o loop,ro "$ISO" "$TMP_DIR/mnt"

    # Extract .iso contents
    cp -rT "$TMP_DIR/mnt" "$TMP_DIR/contents"

    # Unmount .iso so it can be overwritten
    umount "$TMP_DIR/mnt"

    # Perform magic
    mkisofs \
        -U \
        -A "$NAME $VERSION ${CODENAME^}" \
        -V "$NAME $VERSION ${CODENAME^}" \
        -volset "$NAME $VERSION ${CODENAME^}" \
        -J \
        -joliet-long \
        -r \
        -quiet \
        -T \
        -o binary.hybrid.iso \
        -b "isolinux/isolinux.bin" \
        -c "isolinux/boot.cat" \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e "boot/grub/efi.img" \
        -no-emul-boot \
        "$TMP_DIR/contents"

    # CD and USB boot support
    isohybrid --uefi "$ISO"
}

build () {
    BUILD_ARCH="$1"

    #  block size, compression, filter optimization
    export MKSQUASHFS_OPTIONS="-b 128k -comp xz -Xbcj x86"

    mkdir -p "$BASE_DIR/tmp/$BUILD_ARCH"
    cd "$BASE_DIR/tmp/$BUILD_ARCH" || exit

    if [ ! -f ubuntu.iso ]; then
        echo "downloading ubuntu iso..."
        wget -q --show-progress --progress=bar:force:noscroll  2>&1 "http://releases.ubuntu.com/$BASECODENAME/ubuntu-$BASEVERSION-desktop-$BUILD_ARCH.iso" --output-document ubuntu.iso \
        || wget -q --show-progress --progress=bar:force:noscroll  2>&1 "http://cdimage.ubuntu.com/$BASECODENAME/daily-live/current/$BASECODENAME-desktop-$BUILD_ARCH.iso" --output-document ubuntu.iso
    fi

    # remove old configs and copy over new
    rm -rf config auto
    cp -r "$BASE_DIR"/etc/* .

    sed -i "s/all/$BUILD_ARCH/" terraform.conf
    sed -i "s/@SYSLINUX/$CODENAME/" auto/config

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

    uefi binary.hybrid.iso

    md5sum binary.hybrid.iso > binary.hybrid.iso.md5.txt
    sha256sum binary.hybrid.iso > binary.hybrid.iso.sha256.txt

    YYYYMMDD="$(date +%Y%m%d)"
    OUTPUT_DIR="$BASE_DIR/builds/$YYYYMMDD/$BUILD_ARCH"
    mkdir -p "$OUTPUT_DIR"
    mv binary.hybrid.iso "$OUTPUT_DIR/elementaryos-$VERSION-$CHANNEL.$YYYYMMDD.iso"
    mv binary.* "$OUTPUT_DIR/"
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
