#!/bin/bash

export controller_name=controller
export controller_ip=192.168.100.21
compute_ip=192.168.100.22
cinder_ip=192.168.100.23
admin_passwd=123456
mysql_passwd=123456
rabbit_passwd=123456
keystone_passwd=123456
glance_passwd=123456
placement_passwd=123456
nova_passwd=123456
neutron_passwd=123456
cinder_passwd=123456

install_config(){
    hostnamectl set-hostname ${controller_name}
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
    yum install mariadb mariadb-server python2-PyMySQL -y

cat > /etc/my.cnf.d/openstack.cnf << EOF 
[mysqld]
bind-address = ${controller_ip}
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

    systemctl enable mariadb.service
    systemctl start mariadb.service
    mysql_secure_installation

    yum install rabbitmq-server -y
    systemctl enable rabbitmq-server.service
    systemctl start rabbitmq-server.service
    rabbitmqctl add_user openstack ${rabbit_passwd}
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"

    yum install memcached python-memcached -y
    sed -i "s/OPTIONS=\"\"/OPTIONS=\"-l 127.0.0.1,::1,${controller_name}\"/g" /etc/sysconfig/memcached
    systemctl enable memcached.service
    systemctl start memcached.service

    yum install etcd -y 
    sed -i  's/#ETCD_LISTEN_/ETCD_LISTEN_/g' /etc/etcd/etcd.conf
    sed -i  's/#ETCD_INITIAL_/ETCD_INITIAL_/g' /etc/etcd/etcd.conf 
    sed -i  "s/http:\/\/localhost:/http:\/\/${controller_ip}:/g" /etc/etcd/etcd.conf
    sed -i  's/default/controller/g' /etc/etcd/etcd.conf
    sed -i  's/etcd-cluster/etcd-cluster-01/g' /etc/etcd/etcd.conf
    systemctl enable etcd && systemctl start etcd 
    
}

install_keystone(){
mysql -uroot -p${mysql_passwd} -e "create database keystone;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on keystone.* to 'keystone'@localhost identified by '${keystone_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on keystone.* to 'keystone'@'%' identified by '${keystone_passwd}';"

yum install openstack-keystone httpd mod_wsgi -y 
cp  /etc/keystone/keystone.conf   /etc/keystone/keystone.conf.bak
cat >  /etc/keystone/keystone.conf << EOF
[database]
connection = mysql+pymysql://keystone:${keystone_passwd}@controller/keystone
[token]
provider = fernet
EOF

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password ${admin_passwd} \
--bootstrap-admin-url http://controller:5000/v3/ \
--bootstrap-internal-url http://controller:5000/v3/ \
--bootstrap-public-url http://controller:5000/v3/ \
--bootstrap-region-id RegionOne

sed -i "s/#ServerName www.example.com:80/ServerName ${controller_name}/g" /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl enable httpd.service && systemctl start httpd.service

cat > /root/admin-openrc << EOF
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=${admin_passwd}
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

chmod +x /root/admin-openrc
source /root/admin-openrc
openstack domain create --description "An Example Domain" example
openstack project create --domain default \
--description "Service Project" service
openstack project create --domain default \
--description "Demo Project" myproject
openstack user create --domain default \
--password 123456 myuser
openstack role create myrole
openstack role add --project myproject --user myuser myrole

}

install_glance(){

mysql -uroot -p${mysql_passwd} -e "create database glance;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on glance.* to 'glance'@localhost identified by '${glance_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on glance.* to 'glance'@'%' identified by '${glance_passwd}';"

source /root/admin-openrc
openstack user create --domain default --password ${glance_passwd} glance
openstack role add --project service --user glance admin
openstack service create --name glance \
--description "OpenStack Image" image
openstack endpoint create --region RegionOne \
image public http://controller:9292
openstack endpoint create --region RegionOne \
image internal http://controller:9292
openstack endpoint create --region RegionOne \
image admin http://controller:9292

yum install openstack-glance -y
cp /etc/glance/glance-api.conf  /etc/glance/glance-api.conf.bak

cat > /etc/glance/glance-api.conf  << EOF
[database]
connection = mysql+pymysql://glance:${glance_passwd}@controller/glance

[keystone_authtoken]
www_authenticate_uri  = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = ${glance_passwd}

[paste_deploy]
flavor = keystone

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
EOF

su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable openstack-glance-api.service
systemctl start openstack-glance-api.service
}


install_placement(){
mysql -uroot -p${mysql_passwd} -e "create database placement;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on placement.* to 'placement'@localhost identified by '${placement_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on placement.* to 'placement'@'%' identified by '${placement_passwd}';"

source /root/admin-openrc
openstack user create --domain default --password ${placement_passwd} placement
openstack role add --project service --user placement admin
openstack service create --name placement \
  --description "Placement API" placement
openstack endpoint create --region RegionOne \
  placement public http://controller:8778
openstack endpoint create --region RegionOne \
  placement internal http://controller:8778
openstack endpoint create --region RegionOne \
  placement admin http://controller:8778

yum install openstack-placement-api -y
cp  /etc/placement/placement.conf  /etc/placement/placement.conf.bak
cat >  /etc/placement/placement.conf << EOF
[placement_database]

connection = mysql+pymysql://placement:${placement_passwd}@controller/placement
[api]
auth_strategy = keystone

[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = ${placement_passwd}
EOF

su -s /bin/sh -c "placement-manage db sync" placement
systemctl restart httpd

}


install_nova(){
mysql -uroot -p${mysql_passwd} -e "create database nova_cell0;"
mysql -uroot -p${mysql_passwd} -e "create database nova_api;"
mysql -uroot -p${mysql_passwd} -e "create database nova;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova.* to 'nova'@localhost identified by '${nova_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova.* to 'nova'@'%' identified by '${nova_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova_api.* to 'nova'@localhost identified by '${nova_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova_api.* to 'nova'@'%' identified by '${nova_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova_cell0.* to 'nova'@localhost identified by '${nova_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on nova_cell0.* to 'nova'@'%' identified by '${nova_passwd}';"

source /root/admin-openrc
openstack user create --domain default --password  ${nova_passwd} nova
openstack role add --project service --user nova admin
openstack service create --name nova \
  --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne \
  compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne \
  compute admin http://controller:8774/v2.1

yum install openstack-nova-api openstack-nova-conductor \
  openstack-nova-novncproxy openstack-nova-scheduler -y 

cp /etc/nova/nova.conf /etc/nova/nova.conf.bak
cat > /etc/nova/nova.conf << EOF
[DEFAULT]
enabled_apis = osapi_compute,metadata
transport_url = rabbit://openstack:${rabbit_passwd}@controller:5672/
my_ip = ${controller_ip}
use_neutron = true
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[api_database]
connection = mysql+pymysql://nova:${nova_passwd}@controller/nova_api

[database]
connection = mysql+pymysql://nova:${nova_passwd}@controller/nova

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
server_listen = \$my_ip
server_proxyclient_address = \$my_ip

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

[scheduler]
discover_hosts_in_cells_interval = 300

EOF

cat > /etc/httpd/conf.d/00-placement-api.conf << EOF
Listen 8778

<VirtualHost *:8778>
  WSGIProcessGroup placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
  WSGIDaemonProcess placement-api processes=3 threads=1 user=placement group=placement
  WSGIScriptAlias / /usr/bin/placement-api
  <IfVersion >= 2.4>
    ErrorLogFormat "%M"
  </IfVersion>
  ErrorLog /var/log/placement/placement-api.log
  <Directory /usr/bin>
   <IfVersion >= 2.4>
      Require all granted
   </IfVersion>
   <IfVersion < 2.4>
      Order allow,deny
      Allow from all
   </IfVersion>
  </Directory>
  #SSLEngine On
  #SSLCertificateFile ...
  #SSLCertificateKeyFile ...
</VirtualHost>

Alias /placement-api /usr/bin/placement-api
<Location /placement-api>
  SetHandler wsgi-script
  Options +ExecCGI
  WSGIProcessGroup placement-api
  WSGIApplicationGroup %{GLOBAL}
  WSGIPassAuthorization On
</Location>

EOF

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

systemctl enable \
    openstack-nova-api.service \
    openstack-nova-scheduler.service \
    openstack-nova-conductor.service \
    openstack-nova-novncproxy.service
systemctl start \
    openstack-nova-api.service \
    openstack-nova-scheduler.service \
    openstack-nova-conductor.service \
    openstack-nova-novncproxy.service

su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova

}


install_neutron(){
mysql -uroot -p${mysql_passwd} -e "create database neutron;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on neutron.* to 'neutron'@localhost identified by '${neutron_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on neutron.* to 'neutron'@'%' identified by '${neutron_passwd}';"

source /root/admin-openrc
openstack user create --domain default --password ${neutron_passwd} neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron \
  --description "OpenStack Networking" network
openstack endpoint create --region RegionOne \
  network public http://controller:9696
openstack endpoint create --region RegionOne \
  network internal http://controller:9696
openstack endpoint create --region RegionOne \
  network admin http://controller:9696

yum install openstack-neutron openstack-neutron-ml2 \
openstack-neutron-linuxbridge ebtables -y
cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak
cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = true
transport_url = rabbit://openstack:${rabbit_passwd}@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true

[database]
connection = mysql+pymysql://neutron:${neutron_passwd}@controller/neutron

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

[nova]
auth_url = http://controller:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = ${nova_passwd}

[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
EOF

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.bak
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security

[ml2_type_flat]
flat_networks = provider

[ml2_type_vxlan]
vni_ranges = 1:1000

[securitygroup]
enable_ipset = true
EOF

cp /etc/neutron/plugins/ml2/linuxbridge_agent.ini /etc/neutron/plugins/ml2/linuxbridge_agent.ini.bak
cat > /etc/neutron/plugins/ml2/linuxbridge_agent.ini << EOF
[linux_bridge]
physical_interface_mappings = provider:ens36

[vxlan]
enable_vxlan = true
local_ip = ${controller_ip}
l2_population = true

[securitygroup]
enable_security_group = true
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver
EOF

cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.bak
cat > /etc/neutron/l3_agent.ini << EOF
[DEFAULT]
interface_driver = linuxbridge
EOF

cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.bak
cat > /etc/neutron/dhcp_agent.ini << EOF
[DEFAULT]
interface_driver = linuxbridge
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
EOF

cat >> /etc/sysctl.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF

modprobe br_netfilter
echo "modprobe br_netfilter" >> /etc/sysconfig/modules/br_netfilter.modules
chmod 755  /etc/sysconfig/modules/br_netfilter.modules

cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.bak
cat > /etc/neutron/metadata_agent.ini << EOF
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = ${neutron_passwd}
EOF

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
service_metadata_proxy = true
metadata_proxy_shared_secret = ${neutron_passwd}
EOF

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
systemctl restart openstack-nova-api.service
systemctl enable neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
systemctl start neutron-server.service \
  neutron-linuxbridge-agent.service neutron-dhcp-agent.service \
  neutron-metadata-agent.service
systemctl enable neutron-l3-agent.service
systemctl start neutron-l3-agent.service
openstack network agent list

}


install_dashboard(){
yum install openstack-dashboard -y
cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.bak

sed -i "s/127.0.0.1/${controller_name}/g"  /etc/openstack-dashboard/local_settings
sed -i "s/horizon.example.com/*/g"   /etc/openstack-dashboard/local_settings
sed -i "s/UTC/Asia\/Shanghai/g"   /etc/openstack-dashboard/local_settings
sed -i '1i WSGIApplicationGroup %{GLOBAL}' /etc/httpd/conf.d/openstack-dashboard.conf
cat >> /etc/openstack-dashboard/local_settings << EOF
SESSION_ENGINE = 'django.contrib.sessions.backends.file'

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': 'controller:11211',
    }
}
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_API_VERSIONS = {
    "identity": 3,
    "image": 2,
    "volume": 3,
}
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "Default"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"
EOF

cd /usr/share/openstack-dashboard
python manage.py make_web_conf --apache > /etc/httpd/conf.d/openstack-dashboard.conf
ln -s /etc/openstack-dashboard /usr/share/openstack-dashboard/openstack_dashboard/conf
echo "WEBROOT = '/dashboard/'"  >>  /etc/openstack-dashboard/local_settings
sed -i 's/WSGIScriptAlias/#WSGIScriptAlias/g'   /etc/httpd/conf.d/openstack-dashboard.conf
sed -i 's/Alias/#Alias/g'  /etc/httpd/conf.d/openstack-dashboard.conf
sed -i '19a WSGIScriptAlias /dashboard /usr/share/openstack-dashboard/openstack_dashboard/wsgi/django.wsgi' /etc/httpd/conf.d/openstack-dashboard.conf
sed -i '24a Alias /dashboard/static /usr/share/openstack-dashboard/static' /etc/httpd/conf.d/openstack-dashboard.conf

systemctl restart httpd.service memcached.service
}


create_test(){
source /root/admin-openrc

openstack network create  --share --external \
  --provider-physical-network provider \
  --provider-network-type flat provider
openstack subnet create --network provider \
  --allocation-pool start=192.168.200.100,end=192.168.200.200 \
  --dns-nameserver 114.114.114.114  --gateway 192.168.200.2 \
  --subnet-range 192.168.200.0/24 provider

openstack network create selfservice
openstack subnet create --network selfservice \
  --dns-nameserver 114.114.114.114 --gateway 172.16.1.1 \
  --subnet-range 172.16.1.0/24 selfservice
openstack router create router
openstack router add subnet router selfservice
openstack router set router --external-gateway provider

openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 test
#ssh-keygen -q -N "" -y
openstack keypair create --public-key ~/.ssh/id_rsa.pub test
openstack server create --flavor test --image test \
  --nic net-id=$(openstack network list|grep 'selfservice' |awk  '{print $2}') --security-group test \
  --key-name test test
}

install_cinder(){
mysql -uroot -p${mysql_passwd} -e "create database cinder;"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on cinder.* to 'cinder'@localhost identified by '${cinder_passwd}';"
mysql -uroot -p${mysql_passwd} -e "grant all privileges on cinder.* to 'cinder'@'%' identified by '${cinder_passwd}';"
source /root/admin-openrc

openstack user create --domain default --password ${cinder_passwd} cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv2 \
  --description "OpenStack Block Storage" volumev2
openstack service create --name cinderv3 \
  --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne \
  volumev2 public http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev2 internal http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev2 admin http://controller:8776/v2/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev3 public http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev3 internal http://controller:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne \
  volumev3 admin http://controller:8776/v3/%\(project_id\)s

yum install openstack-cinder -y

cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.bak
cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
transport_url = rabbit://openstack:${rabbit_passwd}@controller
auth_strategy = keystone
my_ip = ${controller_ip}

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

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF

cat >> /etc/nova/nova.conf << EOF
[cinder]
os_region_name = RegionOne
EOF

su -s /bin/sh -c "cinder-manage db sync" cinder
systemctl restart openstack-nova-api.service
systemctl enable openstack-cinder-api.service openstack-cinder-scheduler.service
systemctl start openstack-cinder-api.service openstack-cinder-scheduler.service
}

#install_config
#install_keystone
#install_glance
#install_placement
#install_nova
#install_neutron
#install_dashboard
#install_cinder
#create_test