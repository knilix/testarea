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
# Wine
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -c | grep -o '\w*$')/winehq-$(lsb_release -c | grep -o '\w*$').sources"
sudo apt-get update
sudo apt-get install --install-recommends winehq-devel
# Lutris
echo "deb [signed-by=/etc/apt/keyrings/lutris.gpg] https://download.opensuse.org/repositories/home:/strycore/Debian_12/ ./" | sudo tee /etc/apt/sources.list.d/lutris.list > /dev/null
wget -q -O- https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/lutris.gpg > /dev/null
sudo apt-get update
sudo apt-get install lutris -y
# Snap-Packete
sudo snap install musicpod
sudo snap install blue-recorder
sudo snap install discord
sudo snap install obs-studio
# Flatpak
sudo apt-get install flatpak -y
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
#
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip
#
clear
echo #
echo #
echo "- Das Script wurde ausgeführt"
echo "- Nicht mehr benötigte Installationsdateien wieder gelöscht"
echo "- System jetzt neu starten!"
echo #
