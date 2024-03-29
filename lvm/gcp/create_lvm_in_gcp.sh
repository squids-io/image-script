#!/bin/bash
#**********************************************************
#* Author        : tao.zou
#* Last modified : 2021-09-26
#* Filename      : create_lvm_in_gcp.sh
#* Description   : create the lvm volume in gcp instance and mount it to the /squids-data directory.
#                  choose which volumes to use according to the following principles:
#                  1. if ebs volume exists, only use all ebs volumes
#                  2. if there is no ebs volume, use local ssd
#
# warning：        The disk mounting script will judge according to the disk name,
#                  and mount disks with standard names (similar to sdb) first.
#                  There are two types of disks with standard names similar to
#                  sdb in Google Cloud: persistent disk and local SSD in SCSI mode.
#                  When both types of disks exist on the instance,
#                  if you execute this script to mount the disk,
#                  some data will be written to the local SSD,
#                  and there is a risk of data loss. Therefore,
#                  if both types of disks exist on the instance,
#                  please do not execute this script to mount the disks,
#                  otherwise you will be responsible for the consequences.
#* *******************************************************

# mkdir "squids-data"
sudo mkdir -p /squids-data

# find all devices
DEVICES=($(ls /dev/sd[b-z]))
if [[ ${#DEVICES[*]} -eq 0 ]]
then
  DEVICES=($(ls /dev/nvme0n[1-9]))
fi
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
  exit 0
fi
echo "new devices: ${NEWS[*]}"

# create or extend vg & lv
EXIST_VG=$(sudo vgs | grep 'squids-group' | awk '{print $1}')
if [ "$EXIST_VG"x != "squids-group"x ]
then
  sudo vgcreate squids-group ${NEWS[*]}
  sudo lvcreate -l 100%FREE -y -n squids-data squids-group
  sudo mkfs.xfs /dev/squids-group/squids-data
  sudo sed -i '$a /dev/squids-group/squids-data   /squids-data         xfs   defaults,defaults         0 0' /etc/fstab
  sudo mount -a
else
  # mount if necessary
  MOUNTED=$(cat /etc/fstab|grep squids-data|awk '{print $1}')
  if [ ! $MOUNTED ]; then
    sudo sed -i '$a /dev/squids-group/squids-data   /squids-data         xfs   defaults,defaults         0 0' /etc/fstab
    sudo mount -a
    echo "mount success"
  fi

  sudo vgextend squids-group ${NEWS[*]}
  sudo lvresize -l +100%FREE -y /dev/squids-group/squids-data
  sudo xfs_growfs /dev/squids-group/squids-data
fi

echo 'successful'