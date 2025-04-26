#!/bin/bash
# Maintener: @knilix
# Only test
#
# sudo apt install flatpak -y
# flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# root user required (su)
# Now the script
# Startscript: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/flatpak-installs.sh
# Ausführbefehl (einmalig): cd /opt/scriptfiles/testarea-main && ./flatpak-installs.sh
#
flatpak install -y \
  flathub org.gimp.GIMP \
  flathub com.abisource.AbiWord \
  flathub org.blender.Blender \
  flathub net.lutris.Lutris \
  flathub org.kde.kdenlive \
  flathub com.obsproject.Studio \
  flathub org.feichtmeier.Musicpod \
  flathub sa.sy.bluerecorder \
  flathub org.flameshot.Flameshot \
  flathub com.usebottles.bottles
#
# Clean up the installation files
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip
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
