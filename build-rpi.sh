#!/bin/bash

# Install dependencies in host system
apt-get update
apt-get install -y --no-install-recommends ubuntu-keyring debootstrap qemu-user-static qemu-utils qemu-system-arm binfmt-support parted kpartx rsync dosfstools xz-utils wget

# Make sure cross-running ARM ELF executables is enabled
update-binfmts --enable

rootdir=`pwd`
basedir=`pwd`/artifacts/elementary-rpi

# Size of .img file to build in MB. Approx 4GB required at this time, the rest is free space on /
size=8000

export packages="elementary-minimal elementary-desktop elementary-standard"
export architecture="arm64"
export codename="focal"
export codename_latest="groovy"
export channel="daily"

mkdir -p ${basedir}
cd ${basedir}

rm -rf elementary-rpi.img*

# Bootstrap an ubuntu minimal system
debootstrap --foreign --arch $architecture $codename elementary-$architecture http://ports.ubuntu.com/ubuntu-ports

# Add the QEMU emulator for running ARM executables
cp /usr/bin/qemu-arm-static elementary-$architecture/usr/bin/

# Run the second stage of the bootstrap in QEMU
LANG=C chroot elementary-$architecture /debootstrap/debootstrap --second-stage

# Add the rest of the ubuntu repos
cat << EOF > elementary-$architecture/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports $codename main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports $codename-updates main restricted universe multiverse
EOF

# Copy in the elementary PPAs/keys/apt config
for f in ${rootdir}/etc/config/archives/*.list; do cp -- "$f" "elementary-$architecture/etc/apt/sources.list.d/$(basename -- $f)"; done
for f in ${rootdir}/etc/config/archives/*.key; do cp -- "$f" "elementary-$architecture/etc/apt/trusted.gpg.d/$(basename -- $f).asc"; done
for f in ${rootdir}/etc/config/archives/*.pref; do cp -- "$f" "elementary-$architecture/etc/apt/preferences.d/$(basename -- $f)"; done

# Add ubuntu latest repos to get the newest packages to support Raspberry Pi 4
cat << EOF > elementary-$architecture/etc/apt/sources.list.d/latest.list
deb http://ports.ubuntu.com/ubuntu-ports $codename_latest main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports $codename_latest-updates main restricted universe multiverse
EOF

cat << EOF > elementary-$architecture/etc/apt/preferences.d/raspi.pref
Package: linux-firmware-raspi2
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: linux*-raspi*
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: ubuntu-raspi-settings
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: rpi-eeprom
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: libraspberrypi*
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: u-boot-rpi
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Package: grub*
Pin: release n=@LATESTCODENAME
Pin-Priority: 990

Explanation: Uninstall or do not install any Ubuntu-originated
Explanation: package versions other than those in the @BASECODENAME release
Package: *
Pin: release n=@BASECODENAME
Pin-Priority: 900

Package: *
Pin: release o=Ubuntu
Pin-Priority: -10
EOF

# Set codename/channel in added repos
sed -i "s/@CHANNEL/$channel/" elementary-$architecture/etc/apt/sources.list.d/*.list*
sed -i "s/@BASECODENAME/$codename/" elementary-$architecture/etc/apt/sources.list.d/*.list*

# Set codename in added preferences
sed -i "s/@BASECODENAME/$codename/" elementary-$architecture/etc/apt/preferences.d/*.pref*
sed -i "s/@LATESTCODENAME/$codename_latest/" elementary-$architecture/etc/apt/preferences.d/*.pref*

echo "elementary" > elementary-$architecture/etc/hostname

cat << EOF > elementary-${architecture}/etc/hosts
127.0.0.1       elementary    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

mkdir -p elementary-$architecture/etc/oem

wget https://www.raspberrypi.org/app/uploads/2018/03/RPi-Logo-Reg-SCREEN.png \
  -O elementary-$architecture/etc/oem/logo.png

cat > elementary-$architecture/etc/oem.conf << EOF
[OEM]
Manufacturer=Raspberry Pi Foundation
Product=Raspberry Pi
Logo=/etc/oem/logo.png
URL=https://www.raspberrypi.org/
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

# Create the disk and partition it
echo "Creating image file for Raspberry Pi"
dd if=/dev/zero of=${basedir}/elementary-rpi.img bs=1M count=$size
parted elementary-rpi.img --script -- mklabel msdos
parted elementary-rpi.img --script -- mkpart primary fat32 0 256
parted elementary-rpi.img --script -- mkpart primary ext4 256 -1

# Set the partition variables
loopdevice=`losetup -f --show ${basedir}/elementary-rpi.img`
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

# RPi specific config files to configure bootloader
cat << EOF > elementary-$architecture/boot/firmware/config.txt
arm_64bit=1
kernel=vmlinuz
initramfs initrd.img followkernel

enable_uart=1
dtparam=i2c_arm=on
dtparam=spi=on
EOF

cat << EOF > elementary-$architecture/boot/firmware/cmdline.txt
net.ifnames=0 dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=LABEL=writable rootfstype=ext4 elevator=deadline rootwait fixrtc
EOF

# Install Raspberry Pi specific packages
cat << EOF > elementary-$architecture/hardware
#!/bin/bash
apt-get --yes install linux-image-raspi linux-firmware-raspi2 u-boot-rpi grub-efi-arm64 rpi-eeprom ubuntu-raspi-settings

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

# Copy in any file overrides
cp -r ${rootdir}/etc/config/includes.chroot/* elementary-$architecture/

cat << EOF > elementary-$architecture/cleanup
#!/bin/bash
echo "P: Begin executing remove-blacklisted-packages chroot hook..."

dist="\$(lsb_release -c -s -u 2>&1)"||dist="\$(lsb_release -c -s)"

apt-get install --no-install-recommends -f -q -y git

git clone --depth 1 https://github.com/elementary/seeds.git --single-branch --branch $codename
git clone --depth 1 https://github.com/elementary/platform.git --single-branch --branch $codename

for package in \$(cat 'platform/blacklist' 'seeds/blacklist' | grep -v '#'); do
    apt-get autoremove --purge -f -q -y "\$package"
done

apt-get autoremove --purge -f -q -y git

rm -R ../seeds ../platform

rm -rf /root/.bash_history
apt-get clean
rm -f /0
rm -f /hs_err*
rm -f cleanup
rm -f /usr/bin/qemu*

rm -f /var/lib/apt/lists/*_Packages
rm -f /var/lib/apt/lists/*_Sources
rm -f /var/lib/apt/lists/*_Translation-*
EOF

chmod +x elementary-$architecture/cleanup
LANG=C chroot elementary-$architecture /cleanup

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

xz -0 ${basedir}/elementary-rpi.img
