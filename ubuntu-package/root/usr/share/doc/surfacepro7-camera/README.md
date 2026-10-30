# surfacepro7-camera

Front and rear cameras of the Microsoft Surface Pro 7 on Ubuntu, as ordinary
webcams **"Surface Camera Front"** and **"Surface Camera Back"**.

Tested on Ubuntu 26.04 with the linux-surface kernel 7.2.13, Secure Boot on.

## Install

```sh
sudo apt install ./surfacepro7-camera_*.deb
sudo sp7-camera-firmware     # downloads and verifies the ISP firmware
sudo reboot
```

With Secure Boot on, the first DKMS build creates a machine owner key; if the
package tells you so, enroll it (`sudo mokutil --import
/var/lib/shim-signed/mok/MOK.der`), reboot and confirm it in the blue MOK
manager screen. Secure Boot stays on.

## Use

Pick "Surface Camera Front" or "Surface Camera Back" in any application
(Firefox, Chromium, Zoom, ...). The camera starts when an application uses it
and stops when it is released; the camera LED is lit exactly while a camera
runs. Only one camera can stream at a time (the ISP has a single capture
path); requesting the other one switches over.

`sp7-camera-status` shows whether a camera is in use.

## How it works

| Part | What it does |
|---|---|
| DKMS module `surfacepro7-camera-ir` | Intel IPU4P ISP driver and OV5693/OV8865/OV7251 sensor drivers |
| `sp7-camera.service` | loads the drivers at boot after switching only the ISP's IOMMU group to identity mode (required by the driver, DMA protection stays on for all other devices) |
| `sp7-camerad.service` | feeds the two v4l2loopback cameras from libcamera on demand; runs as user `sp7cam` without capabilities, network or write access; libcamera runs in a short-lived child process per session |
| `system-sleep/sp7-camera` | releases the camera before suspend (the ISP driver otherwise blocks suspend while streaming) and restarts it afterwards |
| udev rules | hide the ~55 raw ISP nodes from applications; give `sp7cam` the system DMA heap |
| `/etc/libcamera/ipa/simple/ov8865.yaml` | black level for the rear sensor |

## Known limitations

- Image processing is libcamera's software ISP: good, not phone-grade.
- If `sp7-camerad` itself crashes, an application that was streaming must
  re-open the camera (e.g. reload the page).
- The IR camera (OV7251) is not enabled.
- The drivers are not reloaded at runtime; changes take effect after reboot.

## Remove

```sh
sudo apt purge surfacepro7-camera
```

The firmware in `/usr/lib/firmware/ipu4p_cpd.bin` is left in place.
