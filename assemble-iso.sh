#!/usr/bin/env bash
set -euo pipefail
cd mkosi.output/

SEARCH_DIR=.

DATE=$(just -f ../Justfile _get_timestamp)

PROFILE="${PROFILE:-unknown}"

ISO_LABEL="elementary OS 9"
[[ "$PROFILE" == "daily" ]] && ISO_LABEL+=" Early Access"

ARCH=$(just -f ../Justfile _get_arch)

OUT_ISO="./elementaryos-9.0-${PROFILE}-${ARCH}.${DATE}.iso"

RAW_IMAGE=$(ls elementary_${DATE}.raw)

if [[ -z "$RAW_IMAGE" ]]; then
    echo "error: No .raw image found matching the pattern." >&2
    exit 1
fi

# Detect version
output_dir=$(ls -d liveiso_${DATE})

if [[ -z "$output_dir" ]]; then
    echo "error: No mkosi.output, run just do-daily or do-stable first." >&2
    exit 1
fi

base_name=$(basename "$output_dir")
echo "Detected release target: $base_name"

rm -rf iso_root

rsync -a --delete "${base_name}/iso_root/" iso_root/

echo "Writing minimal APT disc structure for apt-cdrom..."

mkdir -p iso_root/dists/stable/main/binary-amd64
touch iso_root/dists/stable/main/binary-amd64/Packages
gzip -kf iso_root/dists/stable/main/binary-amd64/Packages
mkdir -p iso_root/pool

source ./base_${DATE}/usr/lib/os-release
sed -i "s|%PLACEHOLDER_VERSION%|$PRETTY_NAME|g" iso_root/boot/grub/grub.cfg
sed -i "s|%PLACEHOLDER_VERSION%|$PRETTY_NAME|g" iso_root/.disk/info
sed -i "s|%PLACEHOLDER_ARCH%|${ARCH})|g" iso_root/.disk/info


echo "Creating casper liveiso..."

mkdir -p iso_root/extra

podman run --rm -it \
--network host \
--dns 8.8.8.8 \
-v "$(pwd)":/workspace:Z \
-w /workspace \
ghcr.io/elementary/xorriso:tanit \
sh -c "set -e
           KERNEL_VERSION=\$(ls ${base_name}/lib/modules | head -n 1)
           chroot ${base_name} update-initramfs -u -k \${KERNEL_VERSION}
           cp ${base_name}/boot/vmlinuz-\${KERNEL_VERSION} iso_root/casper/vmlinuz
           cp ${base_name}/boot/initrd.img-\${KERNEL_VERSION} iso_root/casper/initrd
           rm -f iso_root/casper/filesystem.squashfs
           mksquashfs ${base_name} iso_root/casper/filesystem.squashfs -comp zstd
           echo 'Squashing raw image...'
           mksquashfs '$RAW_IMAGE' 'iso_root/extra/$(basename "$RAW_IMAGE").squashfs' -comp zstd
           grub-mkrescue -o ${OUT_ISO} -iso-level 3 -volid \"${ISO_LABEL}\" iso_root/
           echo 'Live environment generated!'"

rm -f custom_ubuntu_live.iso

echo "Success! Your live ISO is at: mkosi.output/$OUT_ISO"
