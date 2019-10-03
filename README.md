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
  <img src="https://github.com/elementary/os/workflows/stable/badge.svg" alt="Stable">
  <img src="https://github.com/elementary/os/workflows/daily/badge.svg" alt="Daily">
</p>

---

## Building Locally

To build an elementary OS image you'll need to:

 1) Make sure you have the following dependencies installed:

    * `dctrl-tools`
    * `dpkg-dev`
    * `genisoimage`
    * `gfxboot-theme-ubuntu`
    * `live-build`
    * `squashfs-tools`
    * `syslinux`
    * `zsync`

 2) Clone this project & `cd` into it:

    ```
    git clone https://github.com/elementary/os && cd os
    ```

 3) Configure the channel in the `etc/terraform.conf` (stable, daily).

 4) Run the build script as a root user:

    ```
    ./terraform.sh
    ```

 5) When done, your images will be in the builds folder

## Contributing

## License
