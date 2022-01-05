#!/bin/bash

version=3.8.4
wget wget --no-check-certificate https://dlcdn.apache.org/maven/maven-3/${version}/binaries/apache-maven-${version}-bin.tar.gz

tar -zxvf apache-maven-${version}-bin.tar.gz -C /usr/local

mv /usr/local/apache* /usr/local/maven

echo "export MavenHome=/usr/locla/maven" >> /etc/profile

echo "export PATH=$PATH:MavenHome/bin" >> /etc/profile

source /etc/profile
