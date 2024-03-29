#!/bin/bash
#**********************************************************
#* Author        : dongyi.zhang
#* Last modified : 2021-05-14
#* Filename      : create_lvm_in_aws.sh
#* Description   : create the lvm volume in Amazon ec2 and mount it to the /squids-data directory.
#                  choose which volumes to use according to the following principles:
#                  1. if ebs volume exists, only use all ebs volumes
#                  2. if there is no ebs volume, use local ssd
#* *******************************************************

# mkdir "squids-data"
sudo mkdir -p /squids-data

# find all devices
DEVICES=($(sudo nvme list |grep -v 'nvme0n1' |grep 'Amazon Elastic Block Store' |awk '{print $1}'))
if [[ ${#DEVICES[*]} -eq 0 ]]
then
  DEVICES=($(sudo nvme list |grep 'Amazon EC2 NVMe Instance Storage' |awk '{print $1}'))
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
