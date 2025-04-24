#!/bin/bash
# Maintener: @knilix
# Only test
#
# Preparation: Ubuntu server 24.04 as basic installation and HWE kernel, then a few commands manually:
###
# sudo apt update && sudo apt upgrade -y
# sudo apt install kubuntu-desktop -y
# sudo apt install language-pack-kde-de -y
# sudo apt-get remove --purge *nvidia*
# sudo add-apt-repository ppa:graphics-drivers/ppa
# sudo apt update && sudo apt install nvidia-driver-570
# sudo nano /etc/default/grub
# Search for the following line:
# GRUB_CMDLINE_LINUX_DEFAULT=""
# Change to:
# GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
# --> Strg-x, y, Enter
# sudo update-grub
# sudo reboot
###
# And now the script
# Startscript: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/u_24.04_selfinstallscript.sh
# Ausführbefehl (einmalig): cd /opt/scriptfiles/testarea-main && ./u_24.04_selfinstallscript.sh
sudo apt update && sudo apt upgrade -y
sudo apt install snapd -y
sudo apt install abiword blender kdenlive plasma-workspace-wayland -y

# Google Chrome Browser
sudo wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb || sudo apt --fix-broken install -y

# Lutris
echo "deb [signed-by=/etc/apt/keyrings/lutris.gpg] https://download.opensuse.org/repositories/home:/strycore/Debian_12/ ./" | sudo tee /etc/apt/sources.list.d/lutris.list > /dev/null
wget -q -O- https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/lutris.gpg > /dev/null
sudo apt update
sudo apt install lutris -y

# Snap packages
snap install musicpod
snap install blue-recorder
snap install discord
snap install obs-studio

# Flatpak
sudo apt install flatpak -y
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub com.usebottles.bottles

# Wine
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -c | grep -o '\w*$')/winehq-$(lsb_release -c | grep -o '\w*$').sources"
sudo apt update
sudo apt install --install-recommends winehq-devel

# Clean up the installation files
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip

# Perform autoremove
sudo apt autoremove -y

#
clear
echo #
echo #
echo "- The script has been executed"
echo "- Installation files that are no longer required deleted"
echo "- Reboot system now!"
echo #
echo "- Das Script wurde ausgeführt"
echo "- Nicht mehr benötigte Installationsdateien wieder gelöscht"
echo "- System jetzt neu starten!"
echo #
