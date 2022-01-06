#!/bin/bash
export compute_name=compute
export compute_ip=192.168.100.22
controller_ip=192.168.100.21
cinder_ip=192.168.100.23
glance_passwd=123456
placement_passwd=123456
nova_passwd=123456
neutron_passwd=123456
rabbit_passwd=123456


install_config(){

    hostnamectl set-hostname ${compute_name}
    source /etc/profile
    systemctl stop firewalld && systemctl disable firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disable/g'  /etc/sysconfig/selinux
    sed -i '141a filter = [ "a/sda/", "r/.*/"]' /etc/lvm/lvm.conf
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

install_nova(){
yum install openstack-nova-compute -y
cp /etc/nova/nova.conf  /etc/nova/nova.conf.bak
cat > /etc/nova/nova.conf << EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:${rabbit_passwd}@controller
my_ip = ${compute_ip}
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = ${nova_passwd}

[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = \$my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html

[glance]
api_servers = http://controller:9292

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = ${placement_passwd}

[libvirt]
virt_type = qemu

EOF

systemctl enable libvirtd.service openstack-nova-compute.service
systemctl start libvirtd.service openstack-nova-compute.service
}

install_neutron(){
yum install openstack-neutron-linuxbridge ebtables ipset -y

cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak
cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:${rabbit_passwd}@controller
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = ${neutron_passwd}

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak
cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini << EOF
[linux_bridge]
physical_interface_mappings = provider:ens36

[vxlan]
enable_vxlan = true
local_ip = ${compute_ip}
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF

cat >> /etc/sysctl.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF

modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/sysconfig/modules/br_netfilter.modules
chmod 755  /etc/sysconfig/modules/br_netfilter.modules

cat >> /etc/nova/nova.conf << EOF
[neutron]
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = ${neutron_passwd}
EOF

systemctl restart openstack-nova-compute.service
systemctl enable neutron-linuxbridge-agent.service
systemctl start neutron-linuxbridge-agent.service
}

install_config
install_nova
install_neutron