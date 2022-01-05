#!/bin/bash

wget https://nodejs.org/dist/v16.13.1/node-v16.13.1-linux-x64.tar.gz

tar -zxvf node-v16.13.1-linux-x64.tar.gz -C /usr/local

mv /usr/local/node* /usr/local/node 

echo "export PATH=$PATH:/usr/local/node/bin" >> /etc/profile

source /etc/profile
