## K8s 跨 vpc 部署，k8s node 所在主机的公网 ipv4 可能会发生改变，解决此问题

### 脚本说明
- applyhostipv4.sh 获取主机 ipv4 并应用主机 ipv4 到 kubelet 启动参数及 k8s node
- apply-host-ipv4.service Linux systemd 启动上述的脚本

### 使用方法
- os 镜像内新建文件夹 /etc/squids
- 从 github 下载 applyhostipv4.sh 到 /etc/squids 目录下
- 从 github 下载 apply-host-ipv4-x.service 到 /lib/systemd/system 目录下
  - aliyun-ecs
    - master 节点：apply-host-ipv4-aliyun-master.service -> /lib/systemd/system/apply-host-ipv4.service
    - node 节点：apply-host-ipv4-aliyun-node.service -> /lib/systemd/system/apply-host-ipv4.service
  - aws-ecc
    - master 节点：apply-host-ipv4-aws-master.service -> /lib/systemd/system/apply-host-ipv4.service
    - node 节点：apply-host-ipv4-aws-node.service -> /lib/systemd/system/apply-host-ipv4.service
  - gcp-ge
    - master 节点：apply-host-ipv4-gcp-ge-master.service -> /lib/systemd/system/apply-host-ipv4.service
    - node 节点：apply-host-ipv4-gcp-ge-node.service -> /lib/systemd/system/apply-host-ipv4.service
  - azure-vm
    - master 节点：apply-host-ipv4-azure-vm-master.service -> /lib/systemd/system/apply-host-ipv4.service
    - node 节点：apply-host-ipv4-azure-vm-node.service -> /lib/systemd/system/apply-host-ipv4.service
- sudo systemctl enable apply-host-ipv4.service