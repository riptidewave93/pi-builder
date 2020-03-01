# pi-builder

This is the source code to my Raspberry Pi minimal image builder called pi-builder.

Please modify the cron.sh and build-image.sh variables before running!

## Required Debian Packages:

```
binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools
```

## How To Use:

 * `./cron.sh` - call from cronjob to build both builds/move to final location
 * `./build-image.sh *distro*` - Used to create a image file

## Distro Options:

 * debian
 * debian-hf
 * raspbian

This is a heavily modified version of <a href="https://github.com/hoedlmoser">hoedlmosers</a> work that can be found at https://kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh

## To Do
 * LOTS of Error Checking
