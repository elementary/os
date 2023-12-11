#!/bin/bash

# fail on first error
set -e

rootdir=$(pwd)

export architecture=amd64
export channel=daily
export codename=jammy
export packages="systemd-sysv linux-image-generic grub-pc ostree-boot elementary-minimal elementary-desktop elementary-standard"
export version=7
export flatpak_architecture=x86_64
export ostree_branch="io.elementary.desktop/${flatpak_architecture}/${version}"

builddir=artifacts/${ostree_branch}
ostree_repo_dir=artifacts/ostree

mkdir -p ${builddir}

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# Install dependencies in host system
apt-get update
apt-get install -y --no-install-recommends ubuntu-keyring ca-certificates debootstrap ostree uuid-runtime ostree-boot grub-pc-bin

# Bootstrap an ubuntu minimal system
debootstrap --arch ${architecture} ${codename} ${builddir} http://archive.ubuntu.com/ubuntu

# Add the rest of the ubuntu repos
cat << EOF > ${builddir}/etc/apt/sources.list
deb http://archive.ubuntu.com/ubuntu ${codename} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${codename}-updates main restricted universe multiverse
EOF





# Based on https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/deb-ostree-builder
# Ensure that dracut makes generic initramfs instead of looking just
# at the host configuration. This is also in the dracut-config-generic
# package, but that only gets installed after dracut makes the first
# initramfs.
echo "Configuring dracut for generic initramfs"
mkdir -p ${builddir}/etc/dracut.conf.d
cat > ${builddir}/etc/dracut.conf.d/90-deb-ostree.conf <<EOF
# Don't make host-specific initramfs
hostonly=no
EOF




# Copy in the elementary PPAs/keys/apt config
for f in "${rootdir}"/etc/config/archives/*.list; do cp -- "$f" "${builddir}/etc/apt/sources.list.d/$(basename -- "$f")"; done
for f in "${rootdir}"/etc/config/archives/*.key; do cp -- "$f" "${builddir}/etc/apt/trusted.gpg.d/$(basename -- "$f").asc"; done
for f in "${rootdir}"/etc/config/archives/*.pref; do cp -- "$f" "${builddir}/etc/apt/preferences.d/$(basename -- "$f")"; done

# Copy in the elementary PPAs/keys/apt config
for f in "${rootdir}"/etc/config/archives/*.list; do cp -- "$f" "${builddir}/etc/apt/sources.list.d/$(basename -- "$f")"; done
for f in "${rootdir}"/etc/config/archives/*.key; do cp -- "$f" "${builddir}/etc/apt/trusted.gpg.d/$(basename -- "$f").asc"; done
for f in "${rootdir}"/etc/config/archives/*.pref; do cp -- "$f" "${builddir}/etc/apt/preferences.d/$(basename -- "$f")"; done

# Set codename/channel in added repos
sed -i "s/@CHANNEL/${channel}/" ${builddir}/etc/apt/sources.list.d/*.list*
sed -i "s/@BASECODENAME/${codename}/" ${builddir}/etc/apt/sources.list.d/*.list*

# Set codename in added preferences
sed -i "s/@BASECODENAME/${codename}/" ${builddir}/etc/apt/preferences.d/*.pref*

mount -t proc proc ${builddir}/proc
mount -t sysfs sys ${builddir}/sys
mount -o bind /dev/ ${builddir}/dev/
mount -o bind /dev/pts ${builddir}/dev/pts

# Make a third stage that installs all of the metapackages
cat << EOF > ${builddir}/third-stage
#!/bin/bash
apt-get update
apt-get --yes upgrade
apt-get --yes install $packages
rm -f /third-stage
EOF

chmod +x ${builddir}/third-stage
LANG=C chroot ${builddir} /third-stage

echo "elementary" > ${builddir}/etc/hostname

cat << EOF > ${builddir}/etc/hosts
127.0.0.1       elementary    localhost
::1             localhost ip6-localhost ip6-loopback
fe00::0         ip6-localnet
ff00::0         ip6-mcastprefix
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF



# TODO(meisenzahl): configure mount points based on `ostree admin deploy`
# Configure mount points
cat << EOF > ${builddir}/etc/fstab
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc /proc proc nodev,noexec,nosuid 0  0
LABEL=writable    /     ext4    defaults    0 0
LABEL=system-boot       /boot/firmware  vfat    defaults        0       1
EOF

# Copy in any file overrides
cp -r "${rootdir}"/etc/config/includes.chroot/* ${builddir}/

mkdir ${builddir}/hooks
cp "${rootdir}"/etc/config/hooks/live/*.chroot ${builddir}/hooks

hook_files="${builddir}/hooks/*"
for f in $hook_files
do
    base=$(basename "${f}")
    LANG=C chroot ${builddir} "/hooks/${base}"
done

rm -r "${builddir}/hooks"

umount ${builddir}/dev/pts
umount ${builddir}/dev/
umount ${builddir}/sys
umount ${builddir}/proc





# Based on https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/deb-ostree-builder
# Cleanup cruft
echo "Preparing system for OSTree"
rm -rf \
   "${builddir}"/boot/*.bak \
   "${builddir}"/etc/apt/sources.list~ \
   "${builddir}"/etc/apt/trusted.gpg~ \
   "${builddir}"/etc/{passwd,group,shadow,gshadow}- \
   "${builddir}"/var/cache/debconf/*-old \
   "${builddir}"/var/lib/dpkg/*-old \
   "${builddir}"/boot/{initrd.img,vmlinuz} \
   "${builddir}"/{initrd.img,vmlinuz}{,.old}

# Remove dbus machine ID cache (makes each system unique)
rm -f "${builddir}"/var/lib/dbus/machine-id "${builddir}"/etc/machine-id

# Remove resolv.conf copied from the host by debootstrap. The settings
# are only valid on the target host and will be populated at runtime.
rm -f "${builddir}"/etc/resolv.conf

# Remove temporary files
rm -rf "${builddir}"/var/cache/man/*
rm -rf "${builddir}"/tmp "${builddir}"/var/tmp
mkdir -p "${builddir}"/tmp "${builddir}"/var/tmp
chmod 1777 "${builddir}"/tmp "${builddir}"/var/tmp

# OSTree uses a single checksum of the combined kernel and initramfs
# to manage boot. Determine the checksum and rename the files the way
# OSTree expects.
echo "Renaming kernel and initramfs per OSTree requirements"
pushd "${builddir}"/boot >/dev/null

vmlinuz_match=(vmlinuz*)
vmlinuz_file=${vmlinuz_match[0]}
initrd_match=(initrd.img* initramfs*)
initrd_file=${initrd_match[0]}

csum=$(cat ${vmlinuz_file} ${initrd_file} | \
	      sha256sum --binary | \
	      awk '{print $1}')
echo "OSTree boot checksum: ${csum}"

mv ${vmlinuz_file} ${vmlinuz_file}-${csum}
mv ${initrd_file} ${initrd_file/initrd.img/initramfs}-${csum}

popd >/dev/null

# OSTree only commits files or symlinks
echo "Remove everything except files, directories and symlinks"
rm -rf "${builddir}"/dev
find "${builddir}" -type b,c,p,s -exec rm -v {} \;
mkdir -p "${builddir}"/dev

# Fixup home directory base paths for OSTree
sed -i -e 's|DHOME=/home|DHOME=/sysroot/home|g' \
    "${builddir}"/etc/adduser.conf
sed -i -e 's|# HOME=/home|HOME=/sysroot/home|g' \
    "${builddir}"/etc/default/useradd

# Move /etc to /usr/etc.
#
# FIXME: Need to handle passwd and group to be updatable. This can be
# done with libnss-altfiles, though that has other drawbacks.
if [ -d "${builddir}"/usr/etc ]; then
    echo "ERROR: Non-empty /usr/etc found!" >&2
    ls -lR "${builddir}"/usr/etc
    exit 1
fi
mv "${builddir}"/etc "${builddir}"/usr

# Move dpkg database to /usr so it's accessible after the OS /var is
# mounted, but make a symlink so it works without modifications to dpkg
# or apt
mkdir -p "${builddir}"/usr/share/dpkg
if [ -e "${builddir}"/usr/share/dpkg/database ]; then
    echo "ERROR: /usr/share/dpkg/database already exists!" >&2
    ls -lR "${builddir}"/usr/share/dpkg/database >&2
    exit 1
fi
mv "${builddir}"/var/lib/dpkg "${builddir}"/usr/share/dpkg/database
ln -sr "${builddir}"/usr/share/dpkg/database \
   "${builddir}"/var/lib/dpkg

# tmpfiles.d setup to make the ostree root compatible with persistent
# directories in the sysroot.
cat > "${builddir}"/usr/lib/tmpfiles.d/ostree.conf <<EOF
d /sysroot/home 0755 root root -
d /sysroot/root 0700 root root -
d /var/opt 0755 root root -
d /var/local 0755 root root -
d /run/media 0755 root root -
L /var/lib/dpkg - - - - ../../usr/share/dpkg/database
EOF

# Create symlinks in the ostree for persistent directories.
mkdir -p "${builddir}"/sysroot
rm -rf "${builddir}"/{home,root,media,opt} "${builddir}"/usr/local
ln -s /sysroot/ostree "${builddir}"/ostree
ln -s /sysroot/home "${builddir}"/home
ln -s /sysroot/root "${builddir}"/root
ln -s /var/opt "${builddir}"/opt
ln -s /var/local "${builddir}"/usr/local
ln -s /run/media "${builddir}"/media






# Based on https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/deb-ostree-builder
# TODO(meisenzahl): support signing of repo
# Now ready to commit. Make the repo if necessary. An archive-z2 repo
# is used since the intention is to use this repo to serve updates
# from.
mkdir -p "${ostree_repo_dir}"
if [ ! -f "${ostree_repo_dir}"/config ]; then
    echo "Initialiazing OSTree repo ${ostree_repo_dir}"
    ostree --repo="${ostree_repo_dir}" init --mode=archive-z2
fi

# Make the commit. The ostree ref is flatpak style.
commit_opts=(
    --repo="${ostree_repo_dir}"
    --branch="${ostree_branch}"
    --subject="Build elementary OS ${version} ${flatpak_architecture} $(date --iso-8601=seconds)"
    --skip-if-unchanged
    --table-output
)
# for id in ${GPG_SIGN[@]}; do
#     commit_opts+=(--gpg-sign="$id")
# done
# if [ -n "$GPG_HOMEDIR" ]; then
#     commit_opts+=(--gpg-homedir="$GPG_HOMEDIR")
# fi
echo "Committing ${builddir} to ${ostree_repo_dir} branch ${ostree_branch}"
ostree commit "${commit_opts[@]}" "${builddir}"

# Update the repo summary
summary_opts=(
    --repo="${ostree_repo_dir}"
    --update
)
# for id in ${GPG_SIGN[@]}; do
#     summary_opts+=(--gpg-sign="$id")
# done
# if [ -n "$GPG_HOMEDIR" ]; then
#     summary_opts+=(--gpg-homedir="$GPG_HOMEDIR")
# fi
echo "Updating ${ostree_repo_dir} summary file"
ostree summary "${summary_opts[@]}"
