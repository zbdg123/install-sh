#!/bin/bash
version=6.2.6

wget  -O redis https://download.redis.io/releases/redis-${version}.tar.gz

tar -zxvf  redis -C /usr/local

mv /usr/local/redis* /usr/local/redis

mkdir /usr/local/redis/{bin,conf}

cd /usr/local/redis && make 

cp ./redis.conf  ./conf  && cp ./src/redis-server ./bin && cp ./src/redis-cli  ./bin 

echo "PATH=$PATH:/usr/local/redis/bin " >> /etc/profile && source /etc/profile 

nohup /usr/local/redis/bin/redis-server /usr/local/redis/conf/redis.conf &

