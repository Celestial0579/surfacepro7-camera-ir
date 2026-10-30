# Ubuntu package (surfacepro7-camera)

Builds `surfacepro7-camera_<version>_all.deb`: the drivers of this branch
(DKMS), a boot loader for the IOMMU requirement, a sandboxed on-demand camera
daemon, suspend handling and udev rules. What it installs and how it works:
[root/usr/share/doc/surfacepro7-camera/README.md](root/usr/share/doc/surfacepro7-camera/README.md).

```sh
git switch sp7-package
ubuntu-package/build-deb.sh 0.1.0        # -> dist/surfacepro7-camera_0.1.0_all.deb
sudo apt install ./dist/surfacepro7-camera_0.1.0_all.deb
sudo sp7-camera-firmware                 # downloads + verifies the ISP firmware
sudo reboot
```

Tested on a Surface Pro 7, Ubuntu 26.04, linux-surface 7.2.13, Secure Boot on.
