# Contributing

## OSTree based images

> OSTree is an upgrade system for Linux-based operating systems that performs atomic upgrades of complete filesystem trees. It is not a package system; rather, it is intended to complement them. A primary model is composing packages on a server, and then replicating them to clients. The underlying architecture might be summarized as “git for operating system binaries”. It operates in userspace, and will work on top of any Linux filesystem. At its core is a git-like content-addressed object store with branches (or “refs”) to track meaningful filesystem trees within the store. Similarly, one can check out or commit to these branches.

Source: https://ostreedev.github.io/ostree/

References:
- [Debian meets OSTree and Flatpak, a case study: Endless OS - YouTube](https://www.youtube.com/watch?v=XNDlCADG4ws)

### build-ostree-repository.sh

The required steps are performed in Docker as for the other build scripts.

First, some variables are declared. Most of them should be self-explanatory. `flatpak_architecture` is used to later create an OSTree branch that follows the Flatpak naming scheme:

- io.elementary.Platform/x86_64/6
- io.elementary.Sdk/x86_64/6.1

Similar to the ARM based images, a minimal Ubuntu system is created via `debootstrap` at the beginning. To this the extended Ubuntu repositories are added.

To be able to create an OSTree compatible initramfs later, we use [dracut](https://dracut.wiki.kernel.org/index.php/Main_Page). Since the initramfs must not be host-specific, dracut must be configured accordingly.

After that, elementary OS specific configurations are done and the base packages are installed. These steps should also be familiar from the ARM based build scripts.

Next, the rootfs created with `debootstrap` is modified to make it OSTree compatible. These steps are based on [deb-ostree-builder/deb-ostree-builder at 15d8fe91af21592bf323fbf9aaf03b86bbe7359d · dbnicholson/deb-ostree-builder](https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/deb-ostree-builder).

Finally, the modified rootfs is ready to be put into an OSTree repository. If necessary, the repository is created first. Then a commit is generated and finally the repository summary is updated.

This step can take up to an hour, depending on the hardware. The most time-consuming step is the creation of the OSTree. Rebuilding should be faster.

### build-ostree-image.sh

This script is based on [deb-ostree-builder/create-deployment at 15d8fe91af21592bf323fbf9aaf03b86bbe7359d - dbnicholson/deb-ostree-builder](https://github.com/dbnicholson/deb-ostree-builder/blob/15d8fe91af21592bf323fbf9aaf03b86bbe7359d/create-deployment). Only variables were renamed and paths were adjusted.

```
error: Bootloader write config: Failed to execute child process ?grub2-mkconfig? (No such file or directory)
```
