#!/bin/bash

# build your own Raspberry Pi SD card
#
# created by Klaus M Pfeiffer, http://blog.kmp.or.at/ , 2012-06-24
#
# modified by Chris Blake, https://github.com/riptidewave93 , 2013-10-17

# Date format, used in the image file name
mydate=`date +%Y%m%d-%H%M`

# Size of the image and boot partitions
imgsize="1000MB"
bootsize="64M"

# Location of the build environment, where the image will be mounted during build
buildenv="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/BuildEnv"

# folders in the buildenv to be mounted, one for rootfs, one for /boot
# Recommend that you don't change these!
rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

# Set this to 'True' if you want to enable wireless support within the image.
wireless_support="True"

##############################
# No need to edit under this #
##############################

# Check what we are building, and set the required variables
if [ "$1" == "" ]; then
  echo "PI-BUILDER: No Distribution Selected, exiting"
  exit 1
else
  if [ "$1" == "debian" ]; then
    distrib_name="debian"
    deb_mirror="http://http.debian.net/debian"
    deb_release="jessie"
    deb_arch="armel"
  elif [ "$1" == "debian-hf" ]; then
    distrib_name="debian"
    deb_mirror="http://http.debian.net/debian"
    deb_release="jessie"
    deb_arch="armhf"
  elif [ "$1" == "raspbian" ]; then
    distrib_name="raspbian"
    deb_mirror="http://archive.raspbian.org/raspbian"
    deb_release="jessie"
    deb_arch="armhf"
  else
    echo "PI-BUILDER: Invalid Distribution Selected, exiting"
    exit 1
  fi
echo "PI-BUILDER: Building $distrib_name Image"
fi

# Check to make sure this is ran by root
if [ $EUID -ne 0 ]; then
  echo "PI-BUILDER: this tool must be run as root"
  exit 1
fi

# make sure no builds are in process (which should never be an issue)
if [ -e ./.pibuild-$1 ]; then
	echo "PI-BUILDER: Build already in process, aborting"
	exit 1
else
	touch ./.pibuild-$1
fi

# Create the buildenv folder, and image file
echo "PI-BUILDER: Creating Image file"
mkdir -p $buildenv
image="${buildenv}/rpi_${distrib_name}_${deb_release}_${deb_arch}_${mydate}.img"
dd if=/dev/zero of=$image bs=$imgsize count=1
device=`losetup -f --show $image`
echo "PI-BUILDER: Image $image created and mounted as $device"

# Format the image file partitions
echo "PI-BUILDER: Setting up MBR/Partitions"
fdisk $device << EOF
n
p
1

+$bootsize
t
c
n
p
2


w
EOF

# Some systems need partprobe to run before we can fdisk the device
partprobe

# Mount the loopback device so we can modify the image, format the partitions, and mount/cd into rootfs
device=`kpartx -va $image | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
sleep 1 # Without this, we sometimes miss the mapper device!
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2
echo "PI-BUILDER: Formatting Partitions"
mkfs.vfat $bootp
mkfs.ext4 $rootp -L root
mkdir -p $rootfs
mount $rootp $rootfs
cd $rootfs

#  start the debootstrap of the system
echo "PI-BUILDER: Mounted partitions, debootstraping..."
debootstrap --no-check-gpg --foreign --arch $deb_arch $deb_release $rootfs $deb_mirror
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot $rootfs /debootstrap/debootstrap --second-stage

# Mount the boot partition
mount -t vfat $bootp $bootfs

# Start adding content to the system files
echo "PI-BUILDER: Setting up custom files/settings relating to rpi"

# apt mirrors
echo "deb $deb_mirror $deb_release main contrib non-free
deb-src $deb_mirror $deb_release main contrib non-free" > etc/apt/sources.list

# Boot commands
echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait quiet init=/usr/lib/raspi-config/init_resize.sh" > boot/cmdline.txt

# Enable sound, as we load the module
echo "dtparam=audio=on" > boot/config.txt

# Mounts
echo "proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
/dev/mmcblk0p2	/				ext4	defaults		0		1
" > etc/fstab

# Hostname
echo "${distrib_name}" > etc/hostname
echo "127.0.1.1	${distrib_name}" >> etc/host

# Networking
echo "auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 dhcp
" > etc/network/interfaces

# Modules
echo "vchiq
snd_bcm2835
" >> etc/modules

# Console settings
echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	de-latin1-nodeadkeys
" > debconf.set

# If Raspbian, add repo key
if [ "$distrib_name" == "raspbian" ]; then
  LANG=C chroot $rootfs wget $deb_mirror.public.key -O - | apt-key add -
fi
# Third Stage Setup Script (most of the setup process)
echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set
apt-get update
apt-get -y install git-core binutils ca-certificates e2fsprogs ntp parted curl \
fake-hwclock locales console-common openssh-server less vim
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
wget https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update --no-check-certificate
chmod +x /usr/bin/rpi-update
rpi-update
echo \"root:raspberry\" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
sed -i 's/^PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
echo 'HWCLOCKACCESS=no' >> /etc/default/hwclock
echo 'RAMTMP=yes' >> /etc/default/tmpfs
rm -f third-stage
" > third-stage
chmod +x third-stage
LANG=C chroot $rootfs /third-stage

if [ "$wireless_support" == "True" ]; then
	echo "PI-BUILDER: Adding Wireless Support"
	echo "#!/bin/bash
apt-get install -y wireless-tools wpasupplicant
wget http://http.us.debian.org/debian/pool/non-free/f/firmware-nonfree/firmware-realtek_0.43_all.deb -O /root/firmware-realtek_0.43_all.deb
dpkg -i /root/firmware-realtek_0.43_all.deb
rm /root/firmware-realtek_0.43_all.deb
rm -f wifi-support
" > wifi-support
	chmod +x wifi-support
	LANG=C chroot $rootfs /wifi-support
fi

echo "PI-BUILDER: Cleaning up build space/image"

# Cleanup Script
echo "#!/bin/bash
update-rc.d ssh remove
apt-get autoclean
apt-get --purge -y autoremove
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
service ntp stop
rm -rf /boot.bak
rm -r /root/.rpi-firmware > /dev/null 2>&1
rm -f cleanup
" > cleanup
chmod +x cleanup
LANG=C chroot $rootfs /cleanup

# First run script to resize rootfs
mkdir -p usr/lib/raspi-config
wget https://raw.githubusercontent.com/dyne/arm-sdk/0.4/arm/extra/rpi-conf/init_resize.sh -O usr/lib/raspi-config/init_resize.sh
chmod +x usr/lib/raspi-config/init_resize.sh

# startup script to generate new ssh host keys
rm -f etc/ssh/ssh_host_*
echo "PI-BUILDER: Deleted SSH Host Keys. Will re-generate at first boot by user"
cat << EOF > etc/init.d/first_boot
#!/bin/sh
### BEGIN INIT INFO
# Provides:          first_boot
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Generates new ssh host keys on first boot & resizes rootfs
# Description:       Generates new ssh host keys on first boot & resizes rootfs
### END INIT INFO

# Generate SSH keys & enable SSH
ssh-keygen -f /etc/ssh/ssh_host_rsa_key -t rsa -N ""
ssh-keygen -f /etc/ssh/ssh_host_dsa_key -t dsa -N ""
service ssh start
update-rc.d ssh defaults

# Expand rootfs
resize2fs -f /dev/mmcblk0p2

# Cleanup
insserv -r /etc/init.d/first_boot
rm -f \$0
EOF
chmod a+x etc/init.d/first_boot
LANG=C chroot $rootfs insserv etc/init.d/first_boot

# Lets cd back
cd $buildenv && cd ..

# Unmount some partitions
echo "PI-BUILDER: Unmounting Partitions"
umount $bootp
umount $rootp
kpartx -d $image

# Properly terminate the loopback devices
echo "PI-BUILDER: Finished making the image $image"
dmsetup remove_all
losetup -D

# Move image out of builddir, as buildscript will delete it
echo "PI-BUILDER: Moving image out of builddir, compressing, then terminating"
mv ${image} ./rpi_${distrib_name}_${deb_release}_${deb_arch}_${mydate}.img
gzip ./rpi_${distrib_name}_${deb_release}_${deb_arch}_${mydate}.img
rm ./.pibuild-$1
rm -r $buildenv
echo "PI-BUILDER: Finished!"
exit 0
