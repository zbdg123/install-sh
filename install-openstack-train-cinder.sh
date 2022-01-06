#!/bin/bash
export cinder_name=cinder
export cinder_ip=192.168.100.23
controller_ip=192.168.100.21
compute_ip=192.168.100.22
rabbit_passwd=123456
cinder_passwd=123456

install_config(){

    hostnamectl set-hostname ${cinder_name}
    source /etc/profile
    systemctl stop firewalld && systemctl disable firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disable/g'  /etc/sysconfig/selinux
    setenforce 0
    yum upgrade -y

    echo "${controller_ip}  controller" >> /etc/hosts
    echo "${compute_ip}  compute" >> /etc/hosts
    echo "${cinder_ip}  cinder" >> /etc/hosts

    yum install chrony -y && systemctl start chrony
    sed -i 's/server/#server/g' /etc/chrony.conf
    echo "server ntp.aliyun.com iburst" >> /etc/chrony.conf
    systemctl restart chrony 

    yum install centos-release-openstack-train -y
    yum install python-openstackclient openstack-selinux -y
    
}

install_cinder(){

yum install lvm2 device-mapper-persistent-data -y
systemctl enable lvm2-lvmetad.service
systemctl start lvm2-lvmetad.service

pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb
sed -i '141a filter = [ "a/sda/", "a/sdb/", "r/.*/"]' /etc/lvm/lvm.conf

yum install openstack-cinder targetcli python-keystone -y

cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.bak
cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:${rabbit_passwd}@controller
auth_strategy = keystone
my_ip = ${cinder_ip}
enabled_backends = lvm
glance_api_servers = http://controller:9292

[database]
connection = mysql+pymysql://cinder:${cinder_passwd}@controller/cinder

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = ${cinder_passwd}

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = lioadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF

systemctl enable openstack-cinder-volume.service target.service
systemctl start openstack-cinder-volume.service target.service
}

install_config
install_cinder