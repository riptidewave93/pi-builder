#!/bin/bash

# This is the actual build script that will be called vi cronjob
#
# created by Chris Blake, https://github.com/riptidewave93 , 2013-10-16

# Current script location, lets automate this a bit
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Location where you want the log/image file moved too after the build completes
# this script will make a folder in this dir named after the distrib, and put the image file in there
# logs will be inside a folder called logs, inside of the distrib folder that was created.
img_dir="/var/www/builds"

# Build date format that is added to the buildlog file, used by the date command syntax
BuildDateFormat="+%Y%m%d-%H%M"

#################################################
# Start actual code, no need to edit below this #
#################################################

# Build Function, used to, well, call the build script.
function image_build {
  distrib=$1
  BuildDate=$(date $BuildDateFormat)
  ${ScriptDir}/build-image.sh $distrib > ${ScriptDir}/buildlog-$BuildDate.txt 2>&1
}

# Cleanup Function, used to move the image to its proper location
function image_finished {
  distrib=$1
  if [ ! -d "${img_dir}/${distrib}/logs" ]; then
    mkdir -p ${img_dir}/${distrib}/logs
  fi
  mv ${ScriptDir}/buildlog-$BuildDate.txt ${img_dir}/${distrib}/logs/ && chmod 644 ${img_dir}/${distrib}/logs/buildlog-$BuildDate.txt
  mv ${ScriptDir}/rpi_*.img ${img_dir}/${distrib}/ && chmod 644 ${img_dir}/${distrib}/rpi_*.img
}

# Make sure we are root
if [[ $EUID -ne 0 ]]; then
  echo "PI-BUILDER: Please run this as root!" 2>&1
  exit 1
fi

# make sure no builds are in process (which should never be an issue)
if [ -e $ScriptDir/.building ]
then
	echo "PI-BUILDER: Builds are in progress, terminating"
	exit 1
fi

#Start build
touch ${ScriptDir}/.building
touch ${img_dir}/CURRENTLY_BUILDING

# we have two distros, so lets build one at a time, and when done call the cleanup function.
image_build debian
image_finished debian
image_build raspbian
image_finished raspbian

# Finished, clean up
rm ${ScriptDir}/.building
rm ${img_dir}/CURRENTLY_BUILDING
exit 0
