#!/bin/bash
cd
#
apt install bash -y
#
mkdir -p /opt/scriptfiles
touch /opt/scriptfiles/updatescript.sh
touch /opt/scriptfiles/updatelog.txt
#
echo #!/bin/bash | tee -a /opt/scriptfiles/updatescript.sh
echo apt-get update -y | tee -a /opt/scriptfiles/updatescript.sh
echo apt-get upgrade -y | tee -a /opt/scriptfiles/updatescript.sh
echo 'echo d=$(date +%y-%m-%d_%H:%M:%S) | tee -a /opt/scriptfiles/updatelog.txt' | tee -a /opt/scriptfiles/updatescript.sh
#
chmod 700 /opt/scriptfiles/updatescript.sh
#
cd && cd /opt/scriptfiles
./updatescript.sh
#
rm -r /opt/scriptfiles/testarea-main
