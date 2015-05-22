#!/bin/bash

# build your own Raspberry Pi SD card
#
# created by Klaus M Pfeiffer, http://blog.kmp.or.at/ , 2012-06-24
#
# modified by Chris Blake, https://github.com/riptidewave93 , 2013-10-17

# Date format, used in the image file name
mydate=`date +%Y%m%d-%H%M`

# Size of the Boot Partition
bootsize="64M"

# Location of the build environment, where the image will be mounted during build
buildenv="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/BuildEnv"

# folders in the buildenv to be mounted, one for rootfs, one for /boot
# Recommend that you don't change these!
rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

##############################
# No need to edit under this #
##############################

# make sure no builds are in process (which should never be an issue)
if [ -e ./.pibuild-$1 ]
then
	echo "PI-BUILDER: Build already in process, aborting"
	exit 1
fi

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

# Create the buildenv folder, and image file
touch ./.pibuild-$1
echo "PI-BUILDER: Creating Image file"
mkdir -p $buildenv
image="${buildenv}/rpi_${distrib_name}_${deb_release}_${mydate}.img"
dd if=/dev/zero of=$image bs=1MB count=1000
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
echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

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
apt-get -y install git-core binutils ca-certificates e2fsprogs ntp parted curl fake-hwclock
wget https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update -O /usr/bin/rpi-update --no-check-certificate
wget https://raw.githubusercontent.com/riptidewave93/raspi-config/master/raspi-config -O /usr/bin/raspi-config --no-check-certificate
chmod +x /usr/bin/rpi-update
chmod +x /usr/bin/raspi-config
mkdir -p /lib/modules/3.1.9+
touch /boot/start.elf
rpi-update
apt-get -y install locales console-common openssh-server less vim
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

echo "PI-BUILDER: Cleaning up build space/image"

# Cleanup Script
echo "#!/bin/bash
update-rc.d ssh remove
apt-get autoclean
apt-get clean
apt-get purge
apt-get update
service ntp stop
#ps ax | grep ntpd | awk '{print $1}' | xargs kill
rm -r /root/.rpi-firmware > /dev/null 2>&1
rm -f cleanup
" > cleanup
chmod +x cleanup
LANG=C chroot $rootfs /cleanup

# startup script to generate new ssh host keys
rm -f etc/ssh/ssh_host_*
echo "PI-BUILDER: Deleted SSH Host Keys. Will re-generate at first boot by user"
cat << EOF > etc/init.d/ssh_gen_host_keys
#!/bin/sh
### BEGIN INIT INFO
# Provides:          Generates new ssh host keys on first boot
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: Generates new ssh host keys on first boot
# Description:       Generates new ssh host keys on first boot
### END INIT INFO
ssh-keygen -f /etc/ssh/ssh_host_rsa_key -t rsa -N ""
ssh-keygen -f /etc/ssh/ssh_host_dsa_key -t dsa -N ""
insserv -r /etc/init.d/ssh_gen_host_keys
service ssh start
update-rc.d ssh defaults
rm -f \$0
EOF
chmod a+x etc/init.d/ssh_gen_host_keys
insserv etc/init.d/ssh_gen_host_keys

# Run Raspi-Config at first login so users can expand storage and such
echo "#!/bin/bash
if [ `id -u` -ne 0 ]; then
  printf \"\nNOTICE: the software on this Raspberry Pi has not been fully configured. Please run 'raspi-config' as root.\n\n\"
else
  raspi-config && exit
fi
" > etc/profile.d/raspi-config.sh
chmod +x etc/profile.d/raspi-config.sh

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
echo "PI-BUILDER: Moving image out of builddir, then terminating"
mv ${image} ./rpi_${distrib_name}_${deb_release}_${mydate}.img
rm ./.pibuild-$1
rm -r $buildenv
echo "PI-BUILDER: Finished!"
exit 0
