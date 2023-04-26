#!/bin/bash
#**********************************************************
#* Author        : xiao.li
#* Last modified : 2021-3-3
#* Filename      : update_lvm_in_huaweiclound.sh
#* Description   : update the lvm volume in huaweiclound ecs and mount it to the /squids-data directory.
#                  choose which volumes to use according to the following principles:
#                  1. if cloud ssd exists, only use all cloud ssd
#                  2. if there is no cloud ssd , use local ssd
#* *******************************************************

# find all devices
DEVICES=($(ls /dev/vd[b-z]))
if [[ ${#DEVICES[*]} -eq 0 ]]
then
  echo 'no block storage device found'
  exit 0
fi
echo "fount devices: ${DEVICES[*]}"

# create or extend vg & lv
EXIST_VG=$(sudo vgs | grep 'squids-group' | awk '{print $1}')
if [ "$EXIST_VG"x == "squids-group"x ]
then
  sudo pvresize ${DEVICES[*]}
  sudo vgextend squids-group ${DEVICES[*]}
  sudo lvresize -l +100%FREE -y /dev/squids-group/squids-data
  sudo xfs_growfs /dev/squids-group/squids-data
fi

echo 'successful'

