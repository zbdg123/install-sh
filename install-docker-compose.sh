#!/bin/bash

mkdir /usr/local/docker-compose
mv ./docker-compose  /usr/local/docker-compose/

echo "export PATH=$PATH:/usr/local/docker-compose" >> /etc/profile
source /etc/profile
