#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
# shellcheck disable=SC1091
source ./terraform.conf
BASE_DIR="$PWD"
ROOT_DIR="$BASE_DIR"/../..

# Make sure cross-running ARM ELF executables is enabled
update-binfmts --enable

if [ "$OEM" == "pinebookpro" ]; then
  echo -e "
#-------------------------------------------#
# BUILD FIRMWARE & PATCHES FOR PINEBOOK PRO #
#-------------------------------------------#
"
  TFA_VERSION=2.3
  UBOOT_VERSION=2020.07
  KERNEL_VERSION=5.8.1
  KERNEL_CHECKSUM="f8d2a4fe938ff7faa565765a52e347e518a0712ca6ddd41b198bd9cc1626a724  linux-$KERNEL_VERSION.tar.xz"

  # download & unpack trusted firmware & u-boot
  curl "https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git/snapshot/trusted-firmware-a-$TFA_VERSION.tar.gz" -o trusted-firmware-a-$TFA_VERSION.tar.gz
  curl "ftp://ftp.denx.de/pub/u-boot/u-boot-$UBOOT_VERSION.tar.bz2" -o u-boot-$UBOOT_VERSION.tar.bz2
  echo "37f917922bcef181164908c470a2f941006791c0113d738c498d39d95d543b21 trusted-firmware-a-$TFA_VERSION.tar.gz" | sha256sum --check
  echo "c1f5bf9ee6bb6e648edbf19ce2ca9452f614b08a9f886f1a566aa42e8cf05f6a u-boot-$UBOOT_VERSION.tar.bz2" | sha256sum --check
  tar xf "trusted-firmware-a-$TFA_VERSION.tar.gz"
  tar xf "u-boot-$UBOOT_VERSION.tar.bz2"

  # Remove tarballs after extraction
  rm "trusted-firmware-a-$TFA_VERSION.tar.gz" "u-boot-$UBOOT_VERSION.tar.bz2"

  # build trusted firmware
  cd "trusted-firmware-a-$TFA_VERSION"
  unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
  CROSS_COMPILE=aarch64-linux-gnu- make PLAT=rk3399
  cp build/rk3399/release/bl31/bl31.elf ../u-boot-$UBOOT_VERSION/
  cd "$BASE_DIR" || exit 1
  rm -rf "trusted-firmware-a-$TFA_VERSION"

  cd u-boot-"$UBOOT_VERSION"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/uboot/0001-Add-regulator-needed-for-usage-of-USB.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/uboot/0002-Correct-boot-order-to-be-USB-SD-eMMC.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/uboot/0003-rk3399-light-pinebook-power-and-standby-leds-during-early-boot.patch"
  sed -i 's/CONFIG_BOOTDELAY=3/CONFIG_BOOTDELAY=0/g' configs/pinebook-pro-rk3399_defconfig

  unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
  CROSS_COMPILE=aarch64-linux-gnu- make pinebook-pro-rk3399_defconfig
  echo 'CONFIG_IDENT_STRING=" elementary ARM"' >> .config
  CROSS_COMPILE=aarch64-linux-gnu- make
  cd "$BASE_DIR"
fi

echo -e "
#--------------------------#
# BOOTSTRAP MINIMAL SYSTEM #
#--------------------------#
"

# Bootstrap an ubuntu minimal system
debootstrap --foreign --arch "$ARCH" "$BASECODENAME" elementary-"$ARCH" http://ports.ubuntu.com/ubuntu-ports

# Add the QEMU emulator for running ARM executables
cp /usr/bin/qemu-arm-static elementary-"$ARCH"/usr/bin/

echo -e "
#--------------------#
# BOOTSTRAP: STAGE 2 #
#--------------------#
"
# Run the second stage of the bootstrap in QEMU
LANG=C chroot elementary-"$ARCH" /debootstrap/debootstrap --second-stage

if [ "$OEM" == "rpi" ]; then
  # Copy Raspberry Pi specific files
  cp -r "$ROOT_DIR"/rpi/rootfs/writable/* elementary-"$ARCH"/
fi

# Add the rest of the ubuntu repos
cat << EOF > elementary-"$ARCH"/etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports "$BASECODENAME" main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports "$BASECODENAME"-updates main restricted universe multiverse
EOF

# Copy in the elementary PPAs/keys/apt config
for f in config/archives/*.list; do cp -- "$f" "elementary-$ARCH/etc/apt/sources.list.d/$(basename -- "$f")"; done
for f in config/archives/*.key; do cp -- "$f" "elementary-$ARCH/etc/apt/trusted.gpg.d/$(basename -- "$f").asc"; done
for f in config/archives/*.pref; do cp -- "$f" "elementary-$ARCH/etc/apt/preferences.d/$(basename -- "$f")"; done

# Set codename/channel in added repos
sed -i "s/@CHANNEL/$CHANNEL/" elementary-"$ARCH"/etc/apt/sources.list.d/*.list*
sed -i "s/@BASECODENAME/$BASECODENAME/" elementary-"$ARCH"/etc/apt/sources.list.d/*.list*

echo "elementary" > elementary-"$ARCH"/etc/hostname

cat << EOF > elementary-"$ARCH"/etc/hosts
127.0.0.1       elementary    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

if [ "$OEM" == "rpi" ]; then
  # Set codename in added preferences
  sed -i "s/@BASECODENAME/$BASECODENAME/" elementary-"$ARCH"/etc/apt/preferences.d/*.pref*

  # Configure mount points
  cp "$ROOT_DIR"/rpi/config/fstab elementary-"$ARCH"/etc/fstab
  export LC_ALL=C
  # Config to stop flash-kernel trying to detect the hardware in chroot
  export FK_MACHINE=none
fi

mount -t proc proc elementary-"$ARCH"/proc
mount -o bind /dev/ elementary-"$ARCH"/dev/
mount -o bind /dev/pts elementary-"$ARCH"/dev/pts

if [ "$OEM" == "rpi" ]; then
  # Make a dummy folder for the boot partition so packages install properly,
  # we'll recreate it on the actual partition later
  CREATE_FIRMWARE_PATH="mkdir -p /boot/firmware"
  EXTRA_PACKAGES="linux-image-raspi linux-firmware-raspi2 pi-bluetooth"
  # Symlink to workaround bug with Bluetooth driver looking in the wrong place for firmware
  EXTRA_STAGES="ln -s /lib/firmware /etc/firmware && rm -rf /boot/firmware hardware"
elif [ "$OEM" == "pinebookpro" ]; then
  CREATE_FIRMWARE_PATH=""
  EXTRA_PACKAGES="initramfs-tools linux-firmware"
  # Remove irqbalance to make shutdown work properly
  EXTRA_STAGES="apt-get --yes remove irqbalance"
fi

# Make a third stage that installs all of the metapackages
cat << EOF > elementary-"$ARCH"/third-stage
#!/bin/bash
apt-get update
apt-get -y upgrade
$CREATE_FIRMWARE_PATH
apt-get -y install elementary-minimal elementary-desktop elementary-standard $EXTRA_PACKAGES
$EXTRA_STAGES
rm -f /third-stage
EOF

echo -e "
#--------------------#
# BOOTSTRAP: STAGE 3 #
#--------------------#
"

# run the third stage
chmod +x elementary-"$ARCH"/third-stage
LANG=C chroot elementary-"$ARCH" /third-stage

if [ -d config/includes.chroot ]; then
  # Copy in any file overrides
  cp -r config/includes.chroot/* elementary-"$ARCH"/
fi

if [ "$OEM" == "rpi" ]; then
  # Support for kernel updates on the Pi 400
  cp "$ROOT_DIR"/rpi/config/flash-kernel-db elementary-"$ARCH"/etc/flash-kernel/db
elif [ "$OEM" == "pinebookpro" ]; then
  echo -e "
#------------------------------------------------#
# BUILD/PATCH FIRMWARE & KERNEL FOR PINEBOOK PRO #
#------------------------------------------------#
"
  # Pull in the wifi and bluetooth firmware from manjaro's git repository.
  git clone --depth 1 https://gitlab.manjaro.org/manjaro-arm/packages/community/ap6256-firmware.git
  cd ap6256-firmware
  mkdir -p brcm
  cp BCM4345C5.hcd brcm/BCM.hcd
  cp BCM4345C5.hcd brcm/BCM4345C5.hcd
  cp nvram_ap6256.txt brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt
  cp fw_bcm43456c5_ag.bin brcm/brcmfmac43456-sdio.bin
  cp brcmfmac43456-sdio.clm_blob brcm/brcmfmac43456-sdio.clm_blob
  mkdir -p elementary-"$ARCH"/lib/firmware/brcm/
  cp -a brcm/* elementary-"$ARCH"/lib/firmware/brcm/

  # Download and build the kernel
  cd elementary-"$ARCH"/usr/src
  curl "http://www.kernel.org/pub/linux/kernel/v5.x/linux-$KERNEL_VERSION.tar.xz" -o linux-$KERNEL_VERSION.tar.xz
  echo "$KERNEL_CHECKSUM" | sha256sum --check

  tar xf "linux-$KERNEL_VERSION.tar.xz"
  rm -f "linux-$KERNEL_VERSION.tar.xz"
  mv "linux-$KERNEL_VERSION" linux
  cd linux
  touch .scmversion
  # ALARM patches
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0001-net-smsc95xx-Allow-mac-address-to-be-set-as-a-parame.patch"     #All

  # Manjaro ARM Patches
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0010-arm64-dts-rockchip-add-cw2015-node-to-PBP.patch"                #Pinebook Pro
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0011-fix-wonky-wifi-bt-on-PBP.patch"                                 #Pinebook Pro
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0012-add-suspend-to-rk3399-PBP.patch"                                #Pinebook Pro
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0013-arm64-dts-rockchip-setup-USB-type-c-port-as-dual-dat.patch"     #Pinebook Pro
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0015-add-dp-alt-mode-to-PBP.patch"                                   #Pinebook Pro

  # Pinebook patches
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0001-Bluetooth-Add-new-quirk-for-broken-local-ext-features-max_page.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0002-Bluetooth-hci_h5-Add-support-for-reset-GPIO.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0003-dt-bindings-net-bluetooth-Add-rtl8723bs-bluetooth.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0004-Bluetooth-hci_h5-Add-support-for-binding-RTL8723BS-with-device-tree.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0005-Bluetooth-btrtl-add-support-for-the-RTL8723CS.patch"
  patch -Np1 -i "$ROOT_DIR/pinebookpro/patches/kernel/0006-bluetooth-btrtl-Make-more-space-for-config-firmware-file-name.patch"

  cp "$ROOT_DIR/pinebookpro/config/kernel/pinebook-pro-5.8.config" .config
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- oldconfig
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- "-j$(nproc)" Image modules
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- DTC_FLAGS="-@" dtbs

  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$BASE_DIR/elementary-$ARCH" modules_install
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_DTBS_PATH="$BASE_DIR/elementary-$ARCH/boot/dtbs" dtbs_install

  cp arch/arm64/boot/Image "$BASE_DIR/elementary-$ARCH/boot"

  # clean up because otherwise we leave stuff around that causes external modules
  # to fail to build.
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper
  cp "$ROOT_DIR/pinebookpro/config/kernel/pinebook-pro-5.8.config" .config

  # Fix symlink for building external modules. kernver is used to we don't need
  # to keep track of the current compiled version
  kernver=$(ls "$BASE_DIR/elementary-$ARCH/lib/modules")
  cd "$BASE_DIR/elementary-$ARCH/lib/modules/$kernver/"
  rm build source
  ln -s /usr/src/linux build
  ln -s /usr/src/linux source
  cd "$BASE_DIR"

  # Build the initramfs for our kernel
  cat << EOF > "$BASE_DIR/elementary-$ARCH/build-initramfs"
#!/bin/bash
update-initramfs -c -k $kernver
rm -f /build-initramfs
EOF

  chmod +x "$BASE_DIR/elementary-$ARCH/build-initramfs"
  LANG=C chroot "$BASE_DIR/elementary-$ARCH" /build-initramfs
fi

echo -e "
#-----------#
# RUN HOOKS #
#-----------#
"

mkdir -p elementary-"$ARCH"/hooks
cp "$ROOT_DIR"/etc/config/hooks/live/*.chroot elementary-"$ARCH"/hooks

for f in elementary-"$ARCH"/hooks/*; do
  LANG=C chroot elementary-"$ARCH" "/hooks/$(basename "$f")"
done

rm -r "elementary-$ARCH/hooks"

# Add a oneshot service to grow the rootfs on first boot
install -m 755 -o root -g root "$ROOT_DIR/$OEM/files/resizerootfs" "elementary-$ARCH/usr/sbin/resizerootfs"
install -m 644 -o root -g root "$ROOT_DIR/pinebookpro/files/resizerootfs.service" "elementary-$ARCH/etc/systemd/system"
mkdir -p "elementary-$ARCH/etc/systemd/system/systemd-remount-fs.service.requires/"
ln -s /etc/systemd/system/resizerootfs.service "elementary-$ARCH/etc/systemd/system/systemd-remount-fs.service.requires/resizerootfs.service"


echo -e "
#-------------------#
# FORMAT FILESYSTEM #
#-------------------#
"

# Set the free space on rootfs to create the image.
raw_size=$((512000+$(du -s -B1K elementary-"$ARCH" | cut -f1)))

YYYYMMDD="$(date +%Y%m%d)"
IMAGE_NAME=elementaryos-$VERSION-$CHANNEL-$OEM-$YYYYMMDD

# Sometimes fallocate fails if the filesystem or location doesn't support it, fallback to slower dd in this case
if ! fallocate -l "$(echo "$raw_size"Ki | numfmt --from=iec-i --to=si --format=%.1f)" "$BASE_DIR/$IMAGE_NAME.img"; then
  dd if=/dev/zero of="$BASE_DIR/$IMAGE_NAME.img" bs=1024 count=$raw_size
fi

parted "$IMAGE_NAME.img" --script -- mklabel msdos

if [ "$OEM" == "rpi" ]; then
  parted "$IMAGE_NAME.img" --script -- mkpart primary fat32 0 256
  parted "$IMAGE_NAME.img" --script -- mkpart primary ext4 256 -1
elif [ "$OEM" == "pinebookpro" ]; then
  parted "$IMAGE_NAME.img" --script -- mkpart primary ext4 32M 100%
fi

# Set the partition variables
loopdevice=$(losetup -f --show "$BASE_DIR/$IMAGE_NAME.img")
device=$(kpartx -va "$loopdevice" | sed 's/.*\(loop[0-9]\+\)p.*/\1/g' | head -1)
sleep 5
device="/dev/mapper/$device"

if [ "$OEM" == "rpi" ]; then
  bootp="$device"p1
  rootp="$device"p2
  # Create file systems
  mkfs.vfat -n system-boot "$bootp"
  mkfs.ext4 -L writable "$rootp"
  # Create the dirs for the partitions and mount them
  mkdir -p "$BASE_DIR/bootp" "$BASE_DIR/root"
  mount -t vfat "$bootp" "$BASE_DIR/bootp"
  mount "$rootp" "$BASE_DIR/root"

  mkdir -p elementary-"$ARCH"/boot/firmware
  mount -o bind "$BASE_DIR/bootp/" elementary-"$ARCH"/boot/firmware
  # Copy Raspberry Pi specific files
  cp -r "$ROOT_DIR"/rpi/rootfs/system-boot/* elementary-"$ARCH"/boot/firmware/

  # Copy kernels and firemware to boot partition
  cat << EOF > elementary-"$ARCH"/hardware
#!/bin/bash

cp /boot/vmlinuz /boot/firmware/vmlinuz
cp /boot/initrd.img /boot/firmware/initrd.img

# Copy device-tree blobs to fat32 partition
cp -r /lib/firmware/*-raspi/device-tree/broadcom/* /boot/firmware/
cp -r /lib/firmware/*-raspi/device-tree/overlays /boot/firmware/

rm -f hardware
EOF

  chmod +x elementary-"$ARCH"/hardware
  LANG=C chroot elementary-"$ARCH" /hardware

  # Grab some updated firmware from the Raspberry Pi foundation
  git clone -b '1.20201022' --single-branch --depth 1 https://github.com/raspberrypi/firmware raspi-firmware
  cp raspi-firmware/boot/*.elf "$BASE_DIR/bootp/"
  cp raspi-firmware/boot/*.dat "$BASE_DIR/bootp/"
  cp raspi-firmware/boot/bootcode.bin "$BASE_DIR/bootp/"

  umount elementary-"$ARCH"/boot/firmware

elif [ "$OEM" == "pinebookpro" ]; then
  rootp="$device"p1
  # Create file systems
  mkfs.ext4 "$rootp"
  # Create filesystems & the dirs for the partitions and mount them
  mkdir -p "$BASE_DIR/root"
  mount "$rootp" "$BASE_DIR/root"

  # Create an fstab so that we don't mount / read-only.
  UUID=$(blkid -s UUID -o value "$rootp")
  echo "UUID=$UUID /               ext4    errors=remount-ro 0       1" >> "$BASE_DIR/elementary-$ARCH/etc/fstab"

  mkdir "$BASE_DIR/elementary-$ARCH/boot/extlinux/"

  # U-boot config
  cat << EOF > "$BASE_DIR/elementary-$ARCH/boot/extlinux/extlinux.conf"
LABEL elementary ARM
KERNEL /boot/Image
FDT /boot/dtbs/rockchip/rk3399-pinebook-pro.dtb
APPEND initrd=/boot/initrd.img-${kernver} console=ttyS2,1500000 console=tty1 root=UUID=$UUID rw rootwait video=eDP-1:1920x1080@60 video=HDMI-A-1:1920x1080@60 quiet splash plymouth.ignore-serial-consoles
EOF

  mkdir -p "$BASE_DIR/elementary-$ARCH/etc/udev/hwdb.d/"
  cp "$ROOT_DIR"/pinebookpro/config/10-usb-kbd.hwdb "$BASE_DIR/elementary-$ARCH/etc/udev/hwdb.d/10-usb-kbd.hwdb"

  # Mark the keyboard as internal, so that "disable when typing" works for the touchpad
  mkdir -p "$BASE_DIR/elementary-$ARCH/etc/libinput/"
  cp "$ROOT_DIR"/pinebookpro/config/local-overrides.quirks "$BASE_DIR/elementary-$ARCH/etc/libinput/local-overrides.quirks"

  # Make resume from suspend work
  sed -i 's/#SuspendState=mem standby freeze/SuspendState=freeze/g' "$BASE_DIR/elementary-$ARCH/etc/systemd/sleep.conf"

  # Disable ondemand scheduler so we can default to schedutil
  rm "$BASE_DIR/elementary-$ARCH/etc/systemd/system/multi-user.target.wants/ondemand.service"

  # Make sound work
  mkdir -p "$BASE_DIR/elementary-$ARCH/var/lib/alsa/"
  cp "$BASE_DIR/elementary-$ARCH/pinebookpro/config/alsa/asound.state" "$BASE_DIR/elementary-$ARCH/var/lib/alsa/"

  # Tweak the minimum frequencies of the GPU and CPU governors to get a bit more performance
  mkdir -p "$BASE_DIR/elementary-$ARCH/etc/tmpfiles.d/"
  cp "$ROOT_DIR"/pinebookpro/config/cpufreq.conf "$BASE_DIR/elementary-$ARCH/etc/tmpfiles.d/cpufreq.conf"
fi

umount "$BASE_DIR/elementary-$ARCH/dev/pts"
umount "$BASE_DIR/elementary-$ARCH/dev/"
umount "$BASE_DIR/elementary-$ARCH/proc"

echo "Rsyncing rootfs into image file"
rsync -HPavz -q "$BASE_DIR/elementary-$ARCH/" "$BASE_DIR/root/"

if [ "$OEM" == "rpi" ]; then
  # Unmount partitions
  umount "$bootp"
  umount "$rootp"
elif [ "$OEM" == "pinebookpro" ]; then
  # Flash u-boot into the early sectors of the image
  cp "$BASE_DIR/u-boot-$UBOOT_VERSION/idbloader.img" "$BASE_DIR/u-boot-$UBOOT_VERSION/u-boot.itb" "$BASE_DIR/root/boot/"
  dd if="$BASE_DIR/u-boot-$UBOOT_VERSION/idbloader.img" of="$loopdevice" seek=64 conv=notrunc
  dd if="$BASE_DIR/u-boot-$UBOOT_VERSION/u-boot.itb" of="$loopdevice" seek=16384 conv=notrunc

  # u-boot now resides in the .img file, clean up the sources so we have space to
  # compress the image
  rm -rf "$BASE_DIR/u-boot-$UBOOT_VERSION"

  # Unmount partitions
  sync
  umount "$rootp"
fi

kpartx -dv "$loopdevice"
losetup -d "$loopdevice"

# clean up root fs now that it resides in the .img file
rm -rf "$BASE_DIR/elementary-$ARCH"

echo "Compressing $IMAGE_NAME.img"
xz -T0 -z "$BASE_DIR/$IMAGE_NAME.img"

cd "$BASE_DIR"

md5sum "$IMAGE_NAME.img.xz" > "$IMAGE_NAME.md5.txt"
sha256sum "$IMAGE_NAME.img.xz" > "$IMAGE_NAME.sha256.txt"

cd "$ROOT_DIR"
