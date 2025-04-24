#!/bin/bash
# Maintener: @knilix
# Only test
# Startscript: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/u_24.04_selfinstallscript.sh
# Ausführbefehl (einmalig): cd /opt/scriptfiles/testarea-main && ./u_24.04_selfinstallscript.sh
sudo apt update
sudo apt upgrade -y
sudo apt install snapd -y
sudo apt-get install abiword -y
sudo apt-get install blender -y
sudo apt-get install kdenlive -y
sudo apt-get install plasma-workspace-wayland -y







sudo apt-get install flatpak -y
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo snap install musicpod
sudo snap install blue-recorder
sudo snap install discord
sudo snap install obs-studio


#
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip
#
clear
echo #
echo #
echo "- Das Script wurde ausgeführt"
echo "- Nicht mehr benötigte Installationsdateien wieder gelöscht"
echo #
