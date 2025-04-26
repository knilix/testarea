#!/bin/bash
# Maintener: @knilix
# Only test
#
# 1. Architektur prüfen
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
  echo "Nur x64-Architekturen werden unterstützt (aktuell: $ARCH)."
  exit 1
fi

# 2. Distribution erkennen
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Konnte die Distribution nicht erkennen."
  exit 1
fi

# 3. Je nach Distribution den Befehl ausführen
case "$DISTRO" in
  debian|ubuntu)
    echo "Debian/Ubuntu erkannt."
    apt install flatpak -y
    ;;
  arch)
    echo "Arch Linux erkannt."
    sudo pacman -S flatpak
    ;;
  fedora)
    echo "Fedora erkannt."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    ;;
  alpine)
    echo "Alpine Linux erkannt."
    apk add flatpak
    ;;
  *)
    echo "Distribution $DISTRO wird nicht unterstützt."
    exit 1
    ;;
esac
#
latpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
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
