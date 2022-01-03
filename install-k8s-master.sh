#!/bin/bash

hostip=192.168.100.1
repository=registry.cn-hangzhou.aliyuncs.com/google_containers

systemctl stop firewalld && systemctl disable firewalld

sed -i 's/SELINUX=enforcing/SELINUX=disable/g'  /etc/sysconfig/selinux

swapoff -a

modprobe br_netfilter

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

cat > /etc/yum.repos.d/kubernets.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

yum install -y kubelet kubeadm kubectl

systemctl enable kubelet && systemctl start kubelet

yum install -y yum-utils device-mapper-persistent-data  lvm2

yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

yum install docker-ce -y

systemctl enable docker && systemctl start docker

cat > /etc/docker/daemon.json << EOF
{ 
  "registry-mirrors": ["https://ji35hxil.mirror.aliyuncs.com"],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload && systemctl restart docker

kubeadm init --apiserver-advertise-address ${hostip}  --image-repository ${repository}  --pod-network-cidr  10.242.0.0/16