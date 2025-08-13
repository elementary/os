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
  <img src="https://github.com/elementary/os/actions/workflows/stable-8.0.yml/badge.svg" alt="Stable 8.0">
  <img src="https://github.com/elementary/os/actions/workflows/daily-8.0.yml/badge.svg" alt="Daily 8.0">
</p>

---

## Building Locally

As elementary OS is built with the Debian version of `live-build`, not the Ubuntu patched version, it's easiest to build an elementary .iso in a Debian VM or container. This prevents messing up your host system too.

The following example assumes you have Docker correctly installed and set up, and that your current working directory is this repo. When done, your image will be in the `builds` folder.

Configure the channel (stable, daily) in the configuration file (`etc/terraform-amd64.conf` or `etc/terraform-arm64.conf` based on your host architecture), then run:

```sh
docker run --rm --privileged -it \
    -v /proc:/proc \
    -v ${PWD}:/working_dir \
    -w /working_dir \
    debian:latest \
    ./build.sh
```

## Further Information

More information about the concepts behind `live-build` and the technical decisions made to arrive at this set of tools to build an .iso can be found [on the wiki](https://github.com/elementary/os/wiki/Building-iso-Images).
