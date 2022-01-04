#!/bin/bash


hostname=localhost
port=8080
crtpath=/root/ca.crt
keypath=/root/ca.key

./install-docker.sh
./install-docker-compose.sh

tar -xf ./harbor.tgz  -C /usr/local/

cd /usr/local/harbor
mv harbor.yml.tmpl  harbor.yml
sed -i 's/hostname: reg.mydomain.com/hostname ${hostname}/g' harbor.yml
sed -i "s/certificate: \/your\/certificate\/path/certificate: ${crtpath}/g"  harbor.yml
sed -i "s/private_key: \/your\/private\/key\/path/private_key: ${keypath}/g" harbor.yml
sed -i "s/port: 80/port: ${port}/g" harbor.yml

./prepare
./install.sh

docker-compose up -d
