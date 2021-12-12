#!/bin/bash
# Based on https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/create-deployment

# fail on first error
set -e

export version=6
export flatpak_architecture=x86_64
export ostree_branch="io.elementary.desktop/${flatpak_architecture}/${version}"

builddir=artifacts/${ostree_branch}
ostree_repo_dir=artifacts/ostree

# Where the checkout of the tree goes
ostree_sysroot=$(mktemp -d -p artifacts ostree-deploy.XXXXXXXXXX)

# Name of the OS for ostree deployment
ostree_os_name=elementary

# The ostree remote URL in installed configuration
ostree_url=https://ostree.elementary.io/

ostree_sysroot_repopath=${ostree_sysroot}/ostree/repo
ostree_sysroot_boot=${ostree_sysroot}/boot

# Install dependencies in host system
dnf install -y ostree grub2

ostree admin init-fs "${ostree_sysroot}"
ostree admin --sysroot="${ostree_sysroot}" os-init ${ostree_os_name}
ostree --repo="${ostree_sysroot_repopath}" remote add ${ostree_os_name} ${ostree_url} \
  ${ostree_branch}
ostree --repo="${ostree_sysroot_repopath}" pull-local --disable-fsync \
  --remote=${ostree_os_name} ${ostree_repo_dir} ${ostree_branch}

# Basic bootloader setup
if [[ "${flatpak_architecture}" == "armhf" ]]; then
  mkdir -p "${ostree_sysroot_boot}"/loader.0
  ln -s loader.0 "${ostree_sysroot_boot}"/loader
  # Empty uEnv.txt otherwise ostree gets upset
  > "${ostree_sysroot_boot}"/loader/uEnv.txt
  ln -s loader/uEnv.txt "${ostree_sysroot_boot}"/uEnv.txt
else
  # Assume grub for all other architectures
  mkdir -p "${ostree_sysroot_boot}"/grub
  # This is entirely using Boot Loader Spec (bls). A more general
  # grub.cfg is likely needed
  cat > "${ostree_sysroot_boot}"/grub/grub.cfg <<"EOF"
insmod blscfg
bls_import
set default='0'
EOF
fi

# Deploy with root=UUID random
uuid=$(uuidgen)
kargs=(--karg=root=UUID=${uuid} --karg=rw --karg=splash \
    --karg=plymouth.ignore-serial-consoles --karg=quiet)
ostree admin --sysroot="${ostree_sysroot}" deploy \
  --os=${ostree_os_name} "${kargs[@]}" \
  ${ostree_os_name}:${ostree_branch}

# Now $ostree_sysroot is ready to be written to some disk