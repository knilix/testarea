#!/bin/bash
cd
#
apt install bash -y
#
mkdir -p /opt/scriptfiles
touch /opt/scriptfiles/updatescript.sh
touch /opt/scriptfiles/updatelog.txt
#
echo apt-get update -y | tee -a /opt/scriptfiles/updatescript.sh
echo apt-get upgrade -y | tee -a /opt/scriptfiles/updatescript.sh
#
echo d=$(date +%y-%m-%d_%H:%M:%S) | tee -a /opt/scriptfiles/updatelog.txt
#
chmod 700 /opt/scriptfiles/updatescript.sh
#
cd && cd /opt/scriptfiles
./updatescript.sh
#
