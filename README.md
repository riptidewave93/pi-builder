pi-builder
==========

This is the source code to my Raspberry Pi minimal image builder called pi-builder. Currently it supports Debian and Raspbian.
This is what powers my build server located at http://pi-builder.servernetworktech.com/

Please modify the pi-builder.sh and build-image.sh veriables before running!

<b>Required Debian Packages:</b>

binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

<b>How To Use:</b>

chmod +x build-image.sh

chmod +x pi-builder.sh

sudo ./pi-builder.sh


This is a heavily modified version of <a href="https://github.com/hoedlmoser">hoedlmosers</a> work that can be found at https://kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh

<b>TO-DO:</b>

LOTS of Error Checking
