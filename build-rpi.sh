#!/bin/bash

set -e

# Install dependencies in host system
apt-get update
apt-get install -y --no-install-recommends ubuntu-keyring debootstrap git qemu-user-static qemu-utils qemu-system-arm binfmt-support parted kpartx rsync dosfstools xz-utils

# Make sure cross-running ARM ELF executables is enabled
update-binfmts --enable

rootdir=`pwd`
basedir=`pwd`/artifacts/elementary-rpi

# Free space on rootfs in MiB
free_space="500"

export packages="elementary-minimal elementary-desktop elementary-standard"
export architecture="arm64"
export codename="focal"
export channel="daily"

version=6.0
YYYYMMDD="$(date +%Y%m%d)"
imagename=elementaryos-$version-$channel-rpi-$YYYYMMDD

mkdir -p ${basedir}
cd ${basedir}

# Bootstrap an ubuntu minimal system
debootstrap --foreign --arch $architecture $codename elementary-$architecture http://ports.ubuntu.com/ubuntu-ports

# Add the QEMU emulator for running ARM executables
cp /usr/bin/qemu-arm-static elementary-$architecture/usr/bin/

# Run the second stage of the bootstrap in QEMU
LANG=C chroot elementary-$architecture /debootstrap/debootstrap --second-stage

# Copy Raspberry Pi specific files
cp -r ${rootdir}/rpi/rootfs/writable/* elementary-${architecture}/

# Add the rest of the ubuntu repos
cat << EOF > elementary-$architecture/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports $codename main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports $codename-updates main restricted universe multiverse
EOF

# Copy in the elementary PPAs/keys/apt config
for f in ${rootdir}/etc/config/archives/*.list; do cp -- "$f" "elementary-$architecture/etc/apt/sources.list.d/$(basename -- $f)"; done
for f in ${rootdir}/etc/config/archives/*.key; do cp -- "$f" "elementary-$architecture/etc/apt/trusted.gpg.d/$(basename -- $f).asc"; done
for f in ${rootdir}/etc/config/archives/*.pref; do cp -- "$f" "elementary-$architecture/etc/apt/preferences.d/$(basename -- $f)"; done

# Set codename/channel in added repos
sed -i "s/@CHANNEL/$channel/" elementary-$architecture/etc/apt/sources.list.d/*.list*
sed -i "s/@BASECODENAME/$codename/" elementary-$architecture/etc/apt/sources.list.d/*.list*

# Set codename in added preferences
sed -i "s/@BASECODENAME/$codename/" elementary-$architecture/etc/apt/preferences.d/*.pref*

echo "elementary" > elementary-$architecture/etc/hostname

cat << EOF > elementary-${architecture}/etc/hosts
127.0.0.1       elementary    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Configure mount points
cat << EOF > elementary-${architecture}/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc /proc proc nodev,noexec,nosuid 0  0
LABEL=writable    /     ext4    defaults,x-systemd.growfs    0 0
LABEL=system-boot       /boot/firmware  vfat    defaults        0       1
EOF

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
# Config to stop flash-kernel trying to detect the hardware in chroot
export FK_MACHINE=none

mount -t proc proc elementary-$architecture/proc
mount -o bind /dev/ elementary-$architecture/dev/
mount -o bind /dev/pts elementary-$architecture/dev/pts

# Make a third stage that installs all of the metapackages
cat << EOF > elementary-$architecture/third-stage
#!/bin/bash
apt-get update
apt-get --yes upgrade
apt-get --yes install $packages

rm -f /third-stage
EOF

chmod +x elementary-$architecture/third-stage
LANG=C chroot elementary-$architecture /third-stage


# Install Raspberry Pi specific packages
cat << EOF > elementary-$architecture/hardware
#!/bin/bash

# Make a dummy folder for the boot partition so packages install properly,
# we'll recreate it on the actual partition later
mkdir -p /boot/firmware

apt-get --yes install linux-image-raspi linux-firmware-raspi2

rm -rf /boot/firmware

rm -f hardware
EOF

chmod +x elementary-$architecture/hardware
LANG=C chroot elementary-$architecture /hardware

# Copy in any file overrides
cp -r ${rootdir}/etc/config/includes.chroot/* elementary-$architecture/

mkdir elementary-$architecture/hooks
cp ${rootdir}/etc/config/hooks/live/*.chroot elementary-$architecture/hooks

for f in elementary-$architecture/hooks/*
do
    base=`basename ${f}`
    LANG=C chroot elementary-$architecture "/hooks/${base}"
done

rm -r "elementary-$architecture/hooks"

# Add a oneshot service to grow the rootfs on first boot
install -m 755 -o root -g root ${rootdir}/rpi/files/resizerootfs "elementary-$architecture/usr/sbin/resizerootfs"
install -m 644 -o root -g root ${rootdir}/pinebookpro/files/resizerootfs.service "elementary-$architecture/etc/systemd/system"
mkdir -p "elementary-$architecture/etc/systemd/system/systemd-remount-fs.service.requires/"
ln -s /etc/systemd/system/resizerootfs.service "elementary-$architecture/etc/systemd/system/systemd-remount-fs.service.requires/resizerootfs.service"

# Calculate the space to create the image.
root_size=$(du -s -B1K elementary-$architecture | cut -f1)
raw_size=$(($((${free_space}*1024))+${root_size}))

# Create the disk and partition it
echo "Creating image file"

# Sometimes fallocate fails if the filesystem or location doesn't support it, fallback to slower dd in this case
if ! fallocate -l $(echo ${raw_size}Ki | numfmt --from=iec-i --to=si --format=%.1f) ${basedir}/${imagename}.img
then
    dd if=/dev/zero of=${basedir}/${imagename}.img bs=1024 count=${raw_size}
fi

parted ${imagename}.img --script -- mklabel msdos
parted ${imagename}.img --script -- mkpart primary fat32 0 256
parted ${imagename}.img --script -- mkpart primary ext4 256 -1

# Set the partition variables
loopdevice=`losetup -f --show ${basedir}/${imagename}.img`
device=`kpartx -va $loopdevice| sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

# Create file systems
mkfs.vfat -n system-boot $bootp
mkfs.ext4 -L writable $rootp

# Create the dirs for the partitions and mount them
mkdir -p ${basedir}/bootp ${basedir}/root
mount -t vfat $bootp ${basedir}/bootp
mount $rootp ${basedir}/root

mkdir -p elementary-$architecture/boot/firmware
mount -o bind ${basedir}/bootp/ elementary-$architecture/boot/firmware

# Copy Raspberry Pi specific files
cp -r ${rootdir}/rpi/rootfs/system-boot/* elementary-${architecture}/boot/firmware/

# Copy kernels and firemware to boot partition
cat << EOF > elementary-$architecture/hardware
#!/bin/bash

cp /boot/vmlinuz /boot/firmware/vmlinuz
cp /boot/initrd.img /boot/firmware/initrd.img

# Copy device-tree blobs to fat32 partition
cp -r /lib/firmware/*-raspi/device-tree/broadcom/* /boot/firmware/
cp -r /lib/firmware/*-raspi/device-tree/overlays /boot/firmware/
cp -r /usr/lib/*-raspi2/* /boot/firmware/

rm -f hardware
EOF

chmod +x elementary-$architecture/hardware
LANG=C chroot elementary-$architecture /hardware

# Grab some updated firmware from the Raspberry Pi foundation
git clone -b '1.20201022' --single-branch --depth 1 https://github.com/raspberrypi/firmware raspi-firmware
cp raspi-firmware/boot/*.elf ${basedir}/bootp/
cp raspi-firmware/boot/*.dat ${basedir}/bootp/
cp raspi-firmware/boot/bootcode.bin ${basedir}/bootp/

umount elementary-$architecture/dev/pts
umount elementary-$architecture/dev/
umount elementary-$architecture/proc
umount elementary-$architecture/boot/firmware

echo "Rsyncing rootfs into image file"
rsync -HPavz -q ${basedir}/elementary-$architecture/ ${basedir}/root/

# Unmount partitions
umount $bootp
umount $rootp
kpartx -dv $loopdevice
losetup -d $loopdevice

echo "Compressing ${imagename}.img"
xz -T0 -z ${basedir}/${imagename}.img

cd "${basedir}"

md5sum ${imagename}.img.xz > ${imagename}.md5.txt
sha256sum ${imagename}.img.xz > ${imagename}.sha256.txt
