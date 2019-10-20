<div align="center">
  <a href="https://elementary.io" align="center">
    <center align="center">
      <img src="https://raw.githubusercontent.com/elementary/brand/master/logomark-black.png" alt="elementary" align="center">
    </center>
  </a>
  <br>
  <h1 align="center"><center>elementary OS</center></h1>
  <h3 align="center"><center>Build scripts for image creation</center></h3>
  <br>
  <br>
</div>

<p align="center">
  <img src="https://github.com/elementary/os/workflows/daily-alternative/badge.svg" alt="Daily">
</p>

---

## Building Locally

As elementary OS is built with the Debian version of `live-build`, not the Ubuntu patched version, it's easiest to build an elementary .iso in a Debian VM or container. This prevents messing up your host system too.

The following example uses Docker and assumes you have Docker correctly installed and set up:

 1) Clone this project & `cd` into it:

    ```
    git clone https://github.com/elementary/os && cd os
    ```

 2) Configure the channel in the `etc/terraform.conf` (stable, daily).

 3) Run the build:

    ```
    mkdir artifacts
    docker run --privileged -i \
        -v /proc:/proc \
        -v ${PWD}/artifacts:/artifacts \
        -v ${PWD}:/working_dir \
        -w /working_dir \
        debian:latest \
        /bin/bash -s etc/terraform.conf < build.sh
    ```

 4) When done, your image will be in the `artifacts` folder.

### The new way

The most significant difference between these .iso build tools and the old tools (pre 5.1) is that pure, unadulterated Debian `live-build` is used instead of the Ubuntu fork. While the Ubuntu fork obviously worked, there have been a lot of nice additions to the upstream version that meant we could remove a lot of the hacky bits from the old scripts.

For example, the Debian `live-build` tools have command line switches to enable/disable UEFI and secure boot support on the resulting .iso. The easiest way for us to achieve this previously was to build an elementary .iso with the Ubuntu `live-build` tools which had no EFI or secure boot support and then graft pieces of an Ubuntu .iso onto it. This left very little room for customisation of the bootloaders as these were just being taken out of an Ubuntu .iso and being told to boot an elementary filesystem.

### File descriptions

#### terraform.sh
This is a custom elementary script used to bootstrap the Debian live-build scripts with variables from a terraform.conf file. It checks for the necessary dependencies (currently just `live-build`) and requires root privileges to run. The .iso building workflows have been tested against live-build 20190311. Recommended to build on a Debian Buster host as this version of `live-build` is available in the repositories. See `.github/workflows/*.yml` for examples building in a Debian Docker container.

#### workflow.sh
This script is ran inside the Debian Buster container in GitHub Actions CI. Essentially just installs the needed dependencies and then runs `terraform.sh`. Notably it uses a specialized azure version of terraform.conf as GitHub CI is hosted in Azure so we can get faster Ubuntu mirrors there.

#### etc/terraform*.conf
Provides a set of commonly used environment variables to be used in the live-build scripts. Reconfigure this file to switch between stable and daily builds and to rebase onto different Ubuntu releases.

#### etc/auto/config
The main entry point into Debian live-build. Options in here shouldn't need to be changed as the variable ones are imported from `terraform.conf`. However, there are a number of notable options in here, including:
- `--bootappend-live` using `maybe-ubiquity` causes ubiquity to launch into a
- `--apt-options` where we set some more forgiving options for apt timeouts and retries in case of temporary mirror issues

#### etc/config/archives/*
A set of apt configuration files and signing keys used to configure extra package repositories. The file extension determines whether the repository is available during the .iso build stage, live/installed systems or both.
- `elementary` is available during both stages and `etc/auto/config` configures it to be either the daily or stable PPA.
- `os-patches` is available during both stages. Notably it also has `.pref` file which sets up pinning to ensure it overrides packages from the Ubuntu repository (even if they're newer)
- `live-team` provides `live-boot` and `live-config` during the .iso build stage which aren't available in the Ubuntu repos
- `appcenter` adds the AppCenter repository for live/installed systems

#### etc/config/hooks/live/000-remove-blacklisted-packages.chroot
This removes packages that are blacklisted in https://github.com/elementary/seeds and https://github.com/elementary/platform from the image (and hence installed system) by cloning the git repositories and iterating through the `blacklist` file in each. The packages that are removed are typically installed as recommends of other packages installed during the build process. This is numbered to run before the apt cleanup hook as it needs to install git to clone the repositories and can't do so without an apt cache.

#### etc/config/hooks/live/999-cleanup-apt-cache.chroot
This removes about 100MB worth of apt packages caches that don't need to remain in the .iso as they will only become stale. Instead of deleting the entire contents of the cache folder, it only deletes specific things so we can ensure that the AppData caches remain in here as they're useful. Be sure to run this hook last, as previous hooks might need to use the cache or may make more mess.

#### etc/config/hooks/live/setup-casper-folder.binary
Due to the fact that Debian live-build would normally use live-boot instead of casper, there are a couple of files that get put in different places and sometimes have different names to what casper and ubiquity expect. We move pretty much everything from the `boot` folder to the `casper` folder, renaming as necessary. We make a copy of the kernel in the `live` folder as the the grub configuration generated by live-build uses that path to detect that this is the right filesystem. It could probably be an empty file, but this is untested.

#### etc/config/hooks/live/set-disk-info.binary
Built .iso images include a `.disk` folder that contains a few files to tell the installer what the OS is. Due to using the Debian version of live-build, these are still a bit Debianized, so we replace them with this hook with some that we've configured in `etc/auto/config`

#### etc/config/includes/binary/*
Files in here are copied to the root of the .iso image.

#### etc/config/includes.binary/.disk
This folder contains the template files for the `.disk` folder mentioned in the `set-disk-info` section above. By nature of the fact that this is an `includes.binary` folder means that the `.disk` folder should be automatically copied into the .iso. However, the live-build task that Debianifies these files runs after the `includes` task, so they get overwritten. We work around this with the `set-disk-info` hook above.

#### etc/config/includes.chroot/*
Files in here are copied to the root of the root filesystem of the live/installed system.

#### etc/config/includes.chroot/etc/apt/apt.conf.d/00trustcdrom
Copy a config file into the root filesystem that causes apt to implicitly trust "CDROM" repositories. This gets put in at a slightly later stage by Ubiquity anyway. We just need it sooner so WiFi drivers in the CD repository can be installed during the live session.

#### etc/config/includes.chroot/etc/netplan/01-network-manager-all.yml
Ubuntu systems by default don't use NetworkManager to manage the network interfaces, and we want to use that. So put this config file in to pass control to NetworkManager.

#### etc/config/includes.chroot/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf
The `01-network-manager-all.yml` file above tells netplan to let NetworkManager manage all interfaces, but NetworkManager by default only manages wireless interfaces, so we reconfigure that to manage all interfaces too.

#### etc/config/package-lists/*
Lists of packages that need installing during the various stages of the build. These lists should not need modifying often as they just pull in metapackages that are generated from the https://github.com/elementary/seeds repository.
- `desktop.list.chroot_install` specifies the main desktop metapackages for the live/installed system
- `desktop.list.chroot_live` specifies extra packages needed for installation (e.g. ubiquity)
- `pool.list.binary` specifies a list of packages to be placed into the .iso as raw .deb files, forming an on "CD" mirror. This allows ubiquity to install the right version of grub for the hardware and install other various bits of firmware or drivers.

