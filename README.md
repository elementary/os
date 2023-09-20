<div align="center">
  <a href="https://elementary.io" align="center">
    <center align="center">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/elementary/brand/master/logomark-white.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/elementary/brand/master/logomark-black.png">
  <img src="https://raw.githubusercontent.com/elementary/brand/master/logomark-black.png" alt="elementary" align="center" height="200">
</picture>
    </center>
  </a>
  <br>
  <h1 align="center"><center>elementary OS</center></h1>
  <h3 align="center"><center>Build scripts for image creation</center></h3>
  <br>
  <br>
</div>

<p align="center">
  <img src="https://github.com/elementary/os/workflows/stable/badge.svg" alt="Stable">
  <img src="https://github.com/elementary/os/actions/workflows/daily-7.1.yml/badge.svg" alt="Daily 7.1">
  <img src="https://github.com/elementary/os/actions/workflows/daily-arm.yml/badge.svg" alt="Daily ARM">

</p>

---

## Building Locally

As elementary OS is built with the Debian version of `live-build`, not the Ubuntu patched version, it's easiest to build an elementary .iso in a Debian VM or container. This prevents messing up your host system too.

The following examples assume you have Docker correctly installed and set up, and that your current working directory is this repo. When done, your image will be in the `builds` folder.

### 64-bit AMD/Intel

Configure the channel in the `etc/terraform.conf` (stable, daily), then run:

```sh
docker run --rm --privileged -it \
    -v /proc:/proc \
    -v ${PWD}:/working_dir \
    -w /working_dir \
    debian:latest \
    ./build.sh etc/terraform.conf
```

### Raspberry Pi 4

```sh
docker run --rm --privileged -it \
    -v /proc:/proc \
    -v ${PWD}:/working_dir \
    -w /working_dir \
    ubuntu:22.04 \
    ./build-rpi.sh
```

### Pinebook Pro

```sh
docker run --rm --privileged -it \
    -v /proc:/proc \
    -v ${PWD}:/working_dir \
    -w /working_dir \
    ubuntu:20.04 \
    ./build-pinebookpro.sh
```

## Further Information

More information about the concepts behind `live-build` and the technical decisions made to arrive at this set of tools to build an .iso can be found [on the wiki](https://github.com/elementary/os/wiki/Building-iso-Images).
