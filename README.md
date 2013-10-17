pi-builder
==========

The source code to my Raspberry Pi system image builder called pi-builder. Currently it supports Debian and Raspbian, and it creates minimal system images.
This code is used on http://pi-builder.servernetworktech.com/ and is ran monthly to create system images.

This is a heavily modified version of <a href="https://github.com/hoedlmoser">hoedlmosers</a> work that can be found at https://kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh

Required Debian Packages:
binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

Please modify the pi-builder.sh and build-image.sh veriables before running!

How To Use:
chmod +x build-image.sh
chmod +x pi-builder.sh
sudo ./pi-builder.sh
