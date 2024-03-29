#!/usr/bin/env bash

# apply host public IPv4 after host restart
# just for aws EC2/aliyun ecs/gcp ge now
# step:
# - get host public IPv4
#   - aws EC2 [https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html]
#   - aliyun ECS [https://help.aliyun.com/document_detail/214777.html?spm=a2c4g.11186623.6.743.1cea639eaI7zwz]
#   - gcp GE [https://stackoverflow.com/questions/23362887/can-you-get-external-ip-address-from-within-a-google-compute-vm-instance]
#   - azure-vm [https://docs.microsoft.com/zh-cn/azure/virtual-machines/linux/instance-metadata-service?tabs=linux#instance-metadata]
#   - huaweicloud-ecs [https://support.huaweicloud.com/usermanual-ecs/ecs_03_0166.html#section13]
#   - qcloud-cvm [https://cloud.tencent.com/document/product/213/4934]
# - create NIC use host public IPv4
# - apply host public IPv4 to kubelet start arg --node-ip
# - use hostname as k8s node name, `kubectl annotate node {node_name} vpc.external.ip={host_public_ip} --overwrite`

# args
# 1. cloud provider
#   - aws
#   - aliyun
#   - gcp-ge
#   - azure-vm
#   - huaweicloud-ecs
#   - qcloud-cvm
# 2. node type
#   - master
#   - node

if [ "$1" == "" ]; then
    echo "err: arg1 means cloud provider, available 'aws', 'aliyun', 'gcp-ge' now"
    exit 0
fi

if [ "$2" == "" ]; then
    echo "err: arg1 means node type, available 'master', 'node'"
    exit 0
fi

# shellcheck disable=SC2068
repeat() { while :; do $@ && return; sleep 1; done }

function loop_exe()
{
    local ex_count=0
    CMDLINE=$1
    while true ; do
        sleep 1
        HOST_PUBLIC_IPv4=`${CMDLINE}`
        if [ $? == 0 ] && [ "$HOST_PUBLIC_IPv4" != "" ]; then
            break;
        else
            (( ex_count = ${ex_count} + 1 ))
            echo "ERROR : The command execute fialed! ex_count = ${ex_count}."
        fi
    done
}

# 获取主机 IPv4
if [ "$1" == "aws" ]; then
    # shellcheck disable=SC2006
    AWSEC2_IMDSV2_TOKEN=`curl -s --connect-timeout 1 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
    # shellcheck disable=SC2006
    loop_exe "curl -s --connect-timeout 1 -H \"X-aws-ec2-metadata-token: $AWSEC2_IMDSV2_TOKEN\" http://169.254.169.254/latest/meta-data/public-ipv4"
elif [ "$1" == "aliyun" ]; then
    # shellcheck disable=SC2006
    ALIYUNECS_METADATA_TOKEN=`curl -s --connect-timeout 1 -X PUT "http://100.100.100.200/latest/api/token" -H "X-aliyun-ecs-metadata-token-ttl-seconds: 21600"`
    # shellcheck disable=SC2006
    loop_exe "curl -s --connect-timeout 1 -H \"X-aliyun-ecs-metadata-token: $ALIYUNECS_METADATA_TOKEN\" http://100.100.100.200/latest/meta-data/eipv4"
elif [ "$1" == "gcp-ge" ]; then
    # shellcheck disable=SC2006
    loop_exe "curl -s --connect-timeout 1 -H \"Metadata-Flavor: Google\" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip"
elif [ "$1" == "azure-vm" ]; then
    # HOST_PUBLIC_IPv4=`curl -s --connect-timeout 1 -H "Metadata:true" --noproxy "*" http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text`
    # shellcheck disable=SC2006
    loop_exe "curl -s --connect-timeout 1 ifconfig.me"
elif [ "$1" == "huaweicloud-ecs" ]; then
    loop_exe "curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/public-ipv4"
elif [ "$1" == "qcloud-cvm" ]; then
    loop_exe "curl -s --connect-timeout 1 http://metadata.tencentyun.com/latest/meta-data/public-ipv4"
elif [ "$1" == "vmware" ]; then
    loop_exe "/etc/squids/getip"
fi

if [ "$HOST_PUBLIC_IPv4" == "" ]; then
    echo "err: get host public IPv4 failed"
    exit 1
fi

# shellcheck disable=SC2027
echo "info: HOST_PUBLIC_IPv4: ""$HOST_PUBLIC_IPv4"

# 仅 k8s node 节点才使用公网 IP 启动 kubelet，用主机公网 IP 新建一个网卡
if [ "$2" == "node" ]; then
  NIC_BRIDGE_NAME="brs"
  if [ -f "/etc/lsb-release" ]; then
    ip link add name ${NIC_BRIDGE_NAME} type bridge
    cat > /etc/netplan/${NIC_BRIDGE_NAME}-config.yaml <<EOF
network:
    version: 2
    renderer: networkd
    ethernets:
        ${NIC_BRIDGE_NAME}:
         addresses:
             - ${HOST_PUBLIC_IPv4}/32
EOF
    netplan apply

    KUBELET_CONF="/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
    # delete old KUBELET_EXTRA_ARGS
    sed -e '/Environment=\"KUBELET_EXTRA_ARGS/d' -i ${KUBELET_CONF}
    # insert
    # todo 确保该处的配置参数跟其他地方的一致
    sed -i '/\[Service\]/aEnvironment="KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --cgroup-driver=systemd --container-runtime-endpoint=unix:///run/containerd/containerd.sock"' ${KUBELET_CONF}
  else
    cat > /etc/sysconfig/network-scripts/ifcfg-${NIC_BRIDGE_NAME} <<EOF
DEVICE=${NIC_BRIDGE_NAME}
ONBOOT=yes
TYPE=Bridge
BOOTPROTO=static
IPADDR=${HOST_PUBLIC_IPv4}
NETMASK=255.255.255.0
EOF
    service network restart
    nmcli device reapply ${NIC_BRIDGE_NAME}

    KUBELET_CONF=`cat /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf | grep EnvironmentFile | grep -v kubeadm | awk -F '=-' '{print $2}'`
    # delete old KUBELET_EXTRA_ARGS
    sed -e '/KUBELET_EXTRA_ARGS=/d' -i ${KUBELET_CONF}
    # insert
    # todo 确保该处的配置参数跟其他地方的一致
    test -s /etc/sysconfig/kubelet && sed -i '$a KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --cgroup-driver=systemd --container-runtime-endpoint=unix:///run/containerd/containerd.sock' /etc/sysconfig/kubelet || echo 'KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --cgroup-driver=systemd --container-runtime-endpoint=unix:///run/containerd/containerd.sock' >> /etc/sysconfig/kubelet
  fi

  # 如果是 centos, kubeadm conf 默认位置不一样
#  CENTOS_ID="CentOS"
#  OS_RELEASE=`awk -F= '/^NAME/{print $2}' /etc/os-release`
#  if [ [ $OS_RELEASE == *$CENTOS_ID* ] ]; then
#      KUBEADM_CONF="/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf"
#  fi

  #if [ `grep -c "Environment=\"KUBELET_EXTRA_ARGS" ${KUBEADM_CONF}` -ne '0' ] && [ `grep -c "\-\-node\-ip" ${KUBEADM_CONF}` -ne '0' ]
  #then
  #  sed -r 's/(\b[0-9]{1,3}\.){3}[0-9]{1,3}\b'/"${HOST_PUBLIC_IPv4}"/ -i ${KUBEADM_CONF}
  #else
  #  sed -i '/\[Service\]/aEnvironment="KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"' ${KUBEADM_CONF}
  #fi

  # 重启 kubelet
  systemctl daemon-reload
  systemctl restart kubelet

  echo 'success apply to nic'
fi

echo 'check k8s api-server'
repeat kubectl api-versions --kubeconfig=/etc/kubernetes/kubelet.conf > /dev/null 2>&1
echo 'k8s api-server running'

# shellcheck disable=SC2006
HOST_NAME=`hostname`

#if [ "$1" == "node" ]; then
# 用本机 kubelet 的配置文件，更新 k8s node 的 annotation
# 必须在 kubeadm join 后，不然没 kubelet.conf
kubectl annotate node "${HOST_NAME}" vpc.external.ip="${HOST_PUBLIC_IPv4}" --kubeconfig=/etc/kubernetes/kubelet.conf --overwrite
echo 'annotate node vpc.external.ip finish'
#fi

if [ "$2" == "master" ]; then
  kubectl label -ndefault service kubernetes vpc.external.ip="${HOST_PUBLIC_IPv4}" --kubeconfig=/root/.kube/config --overwrite
  echo 'label service kubernetes finish'
  kubectl label node "${HOST_NAME}" vpc.external.ip="${HOST_PUBLIC_IPv4}" --kubeconfig=/root/.kube/config --overwrite
  echo 'label master node finish'
fi
