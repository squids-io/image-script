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
for ((i=0; i<${#NEWS[@]}; i++))
do
  EXIST_VG=$(sudo vgs | grep 'squids-group-chi-'${i} | awk '{print $1}')
  if [ "$EXIST_VG"x != 'squids-group-chi-'${i}''x ]
  then
    sudo mkdir -p /squids-data/chi-${i}
    sudo vgcreate squids-group-chi-${i} ${NEWS[$i]}
    sudo lvcreate -l 100%FREE -y -n chi-${i} 'squids-group-chi-'${i}
    sudo mkfs.xfs /dev/squids-group-chi-${i}/chi-${i}
    sudo sed -i '$a /dev/squids-group-chi-'${i}'/chi-'${i}'  /squids-data/chi-'${i}'         xfs   defaults,defaults         0 0' /etc/fstab
    sudo mount -a
  else
    sudo vgextend squids-group-chi-${i} ${NEWS[i]}
    sudo lvresize -l +100%FREE -y /dev/squids-group/chi-${i}
    sudo xfs_growfs /dev/squids-group/chi-${i}
  fi
done

echo 'successful'
