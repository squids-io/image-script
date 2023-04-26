#!/bin/bash
#**********************************************************
#* Author        : huan.yan
#* Last modified : 2021-12-28
#* Filename      : create_lvm_in_aliyun.sh
#* Description   : create the lvm volume in aliyun ecs and mount it to the /squids-data directory.
#                  choose which volumes to use according to the following principles:
#                  1. if cloud ssd exists, only use all cloud ssd
#                  2. if there is no cloud ssd , use local ssd
#* *******************************************************

# mkdir "squids-data"
sudo mkdir -p /squids-data

# find all devices
DEVICES=($(ls /dev/vd[b-z]))
if [[ ${#DEVICES[*]} -eq 0 ]]
then
  echo 'no block storage device found'
  exit 0
fi
echo "fount devices: ${DEVICES[*]}"

# create pv on new devices
declare -a NEWS
for element in ${DEVICES[*]}
do
  FS_TYPE=$(sudo file -s $element | awk '{print $2}')
  if [ "$FS_TYPE"x != "data"x ]
  then
    echo "exist file system on $element"
    continue
  fi
  sudo pvcreate $element
  NEWS=("${NEWS[@]}" $element)
done
if [[ ${#NEWS[*]} -eq 0 ]]
then
  echo 'no new devices found'
  #exit 0
fi
echo "new devices: ${NEWS[*]}"

# create or extend vg & lv
EXIST_VG=$(sudo vgs | grep 'squids-group' | awk '{print $1}')
if [ "$EXIST_VG"x != "squids-group"x ]
then
  echo "create new devices: ${NEWS[*]}"
  sudo vgcreate squids-group ${NEWS[*]}
  sudo lvcreate -l 100%FREE -y -n squids-data squids-group
  sudo mkfs.xfs /dev/squids-group/squids-data
  sudo sed -i '$a /dev/squids-group/squids-data   /squids-data         xfs   defaults,defaults         0 0' /etc/fstab
  sudo mount -a
  echo "mount success"
else
  # vg & lv already exists
  # mount if necessary
  MOUNTED=$(cat /etc/fstab|grep squids-data|awk '{print $1}')
  if [ ! $MOUNTED ]; then
    sudo sed -i '$a /dev/squids-group/squids-data   /squids-data         xfs   defaults,defaults         0 0' /etc/fstab
    sudo mount -a
    echo "mount success"
  fi

  echo "extend devices: ${DEVICES[*]}"
  #sudo vgextend squids-group ${NEWS[*]}
  sudo pvresize ${DEVICES[*]}
  sudo vgextend squids-group ${DEVICES[*]}
  sudo lvresize -l +100%FREE -y /dev/squids-group/squids-data
  sudo xfs_growfs /dev/squids-group/squids-data
fi

echo 'successful'