#!/usr/bin/env bash

# apply host public IPv4 after host restart
# just for aws EC2 now
# step:
# - get host public IPv4
#   - aws EC2 [https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html]
# - create NIC use host public IPv4
# - apply host public IPv4 to kubelet start arg --node-ip
# - use hostname as k8s node name, `kubectl annotate node {node_name} vpc.external.ip={host_public_ip} --overwrite`

# args
# - nic
# - node

#if [ "$1" == "" ]; then
#    echo "err: arg1 must 'nic' or 'node'"
#    exit 0
#fi

# 获取主机 IPv4
# shellcheck disable=SC2006
AWSEC2_IMDSV2_TOKEN=`curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
# shellcheck disable=SC2006
AWSEC2_HOST_PUBLIC_IPv4=`curl -s -H "X-aws-ec2-metadata-token: $AWSEC2_IMDSV2_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4`

#if [ "$1" == "nic" ]; then
# 用主机公网 IP 新建一个网卡
NCI_BRIDGE_NAME="brs"
ip link add name ${NCI_BRIDGE_NAME} type bridge
cat > /etc/netplan/${NCI_BRIDGE_NAME}-config.yaml <<EOF
network:
    version: 2
    renderer: networkd
    ethernets:
        ${NCI_BRIDGE_NAME}:
         addresses:
             - ${AWSEC2_HOST_PUBLIC_IPv4}/24
EOF
netplan apply


# 把主机公网 IP 配置进 kubelet 启动参数里
KUBEADM_CONF="/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

#if [ `grep -c "Environment=\"KUBELET_EXTRA_ARGS" ${KUBEADM_CONF}` -ne '0' ] && [ `grep -c "\-\-node\-ip" ${KUBEADM_CONF}` -ne '0' ]
#then
#  sed -r 's/(\b[0-9]{1,3}\.){3}[0-9]{1,3}\b'/"${AWSEC2_HOST_PUBLIC_IPv4}"/ -i ${KUBEADM_CONF}
#else
#  sed -i '/\[Service\]/aEnvironment="KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${AWSEC2_HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"' ${KUBEADM_CONF}
#fi

# delete old KUBELET_EXTRA_ARGS
sed -e '/Environment=\"KUBELET_EXTRA_ARGS/d' -i ${KUBEADM_CONF}
# insert
# todo 确保该处的配置参数跟其他地方的一致
sed -i '/\[Service\]/aEnvironment="KUBELET_EXTRA_ARGS=--container-runtime=remote --node-ip='"${AWSEC2_HOST_PUBLIC_IPv4}"' --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"' ${KUBEADM_CONF}

# 重启 kubelet
systemctl daemon-reload
systemctl restart kubelet

echo 'success apply to nic'
#fi


#if [ "$1" == "node" ]; then
# 用本机 kubelet 的配置文件，更新 k8s node 的 annotation
# 必须在 kubeadm join 后，不然没 kubelet.conf
# shellcheck disable=SC2006
HOST_NAME=`hostname`
kubectl annotate node "${HOST_NAME}" vpc.external.ip="${AWSEC2_HOST_PUBLIC_IPv4}" --kubeconfig=/etc/kubernetes/kubelet.conf --overwrite
echo 'success apply to node'
#fi