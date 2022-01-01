#!/bin/bash

install -y yum-utils device-mapper-persistent-data  lvm2

yum-config-manager  --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

yum install docker-ce -y
