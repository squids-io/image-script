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

# extend vg & lv
EXIST_VG=$(sudo vgs | grep 'squids-group' | awk '{print $1}')
if [ "$EXIST_VG"x != "squids-group"x ]
then
  sudo vgcreate squids-group ${DEVICES[*]}
  sudo pvresize yes ${DEVICES[*]}
  sudo lvcreate -l 100%FREE -y -n squids-data squids-group
  sudo mkfs.xfs /dev/squids-group/squids-data
  sudo sed -i '$a /dev/squids-group/squids-data   /squids-data         xfs   defaults,defaults         0 0' /etc/fstab
  sudo mount -a
else
  sudo vgextend squids-group ${DEVICES[*]}
  sudo pvresize yes ${DEVICES[*]}
  sudo lvresize -l +100%FREE -y /dev/squids-group/squids-data
  sudo xfs_growfs /dev/squids-group/squids-data
fi

echo 'successful'
