#!/bin/bash
# Maintener: @knilix
# --> Only test - only x64 !
#
# root user benötigt (su)
#
# Für Debian, Ubuntu, Arch, Fedora, Gentoo, FreeBSD und Alpine geeignet.
# Vorher erledigen: 
# - installieren von wget und zip 
#
# Es werden mit diesem Script Flatpak und folgende Apps installiert: Discord, Ginp, AbiWord, Blender, Lutris, Kdenlive, OBSStudio, Misicpod, BlueRecorder, Flameshot, Bottles.
# Es wird geprüft, ob Flatpak installiert ist. Wenn nicht, wird es installiert.
# Es wird geprüft of die zu installierenden Flatpak-Apps schon per Snap oder Nativ installiert sind. Wenn ja, wird die Installation der jeweiligen Flatpak-App übersprungen.
# Warnhinweise, die nur informativ sind und keinerlei Einfluss auf die Funktion der jeweiligen App haben, z.B. weil KDE statt Gnome verwendet wird, werden ausgeblendet.
#
# root user required (su)
#
# Suitable for Debian, Ubuntu, Arch, Fedora, Gentoo, FreeBSD and Alpine.
# Do it beforehand:
# - install wget and zip
#
# This script installs Flatpak and the following apps: Discord, Ginp, AbiWord, Blender, Lutris, Kdenlive, OBSStudio, Misicpod, BlueRecorder, Flameshot, Bottles.
# The system checks whether Flatpak is installed. If not, it is installed.
# The system checks whether the Flatpak apps to be installed are already installed via Snap or Native. If yes, the installation of the respective Flatpak app is skipped.
# Warnings that are only informative and have no influence on the function of the respective app, e.g. because KDE is used instead of Gnome, are hidden.
#
# download and unzip: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/flatpak-installs.sh
# execute (unique): cd /opt/scriptfiles/testarea-main && ./flatpak-installs.sh
#
# Farbdefinitionen
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GRAY='\033[1;37m'
NC='\033[0m' # No Color

# Debug-Modus aktivieren, wenn --debug übergeben wird
if [[ "$1" == "--debug" ]]; then
  echo -e "${YELLOW}Debug-Modus aktiv. Zeige alle Befehle.${NC}"
  set -x
  DEBUG=true
else
  DEBUG=false
fi

echo -e "${GRAY}Starte Skript...${NC}"

# 1. Architektur prüfen
ARCHITECTURE="$(uname -m)"
if [ "$ARCHITECTURE" != "x86_64" ]; then
  echo -e "${RED}Nur x86_64-Architektur wird unterstützt. Beende.${NC}"
  exit 1
fi

# 2. Distribution erkennen
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
elif [ "$(uname -s)" = "FreeBSD" ]; then
  DISTRO="freebsd"
elif [ -f /etc/gentoo-release ]; then
  DISTRO="gentoo"
elif [ -f /etc/funtoo-release ]; then
  DISTRO="gentoo"
elif grep -q "Calculate" /etc/issue 2>/dev/null; then
  DISTRO="gentoo"
else
  echo -e "${RED}Konnte die Distribution nicht erkennen.${NC}"
  exit 1
fi

echo -e "${GREEN}Distribution erkannt: $DISTRO${NC}"

# 3. Paketmanager Befehle setzen
case "$DISTRO" in
  debian|ubuntu)
    PM_UPDATE="apt update -y 2>/dev/null"
    PM_INSTALL="apt install -y 2>/dev/null"
    PM_QUERY="dpkg-query -W -f='\${Status}'"
    CHECK_INSTALLED_STATUS="install ok installed"
    ;;
  arch)
    PM_UPDATE="pacman -Sy --noconfirm"
    PM_INSTALL="pacman -S --noconfirm"
    PM_QUERY="pacman -Q"
    CHECK_INSTALLED_STATUS=""
    ;;
  fedora)
    PM_UPDATE="dnf makecache"
    PM_INSTALL="dnf install -y"
    PM_QUERY="rpm -q"
    CHECK_INSTALLED_STATUS=""
    ;;
  alpine)
    PM_UPDATE="apk update"
    PM_INSTALL="apk add"
    PM_QUERY="apk info -e"
    CHECK_INSTALLED_STATUS=""
    ;;
  gentoo)
    PM_UPDATE="emerge --sync"
    PM_INSTALL="emerge"
    PM_QUERY="equery list"
    CHECK_INSTALLED_STATUS=""
    if ! command -v equery >/dev/null 2>&1; then
      echo -e "${GRAY}Installiere gentoolkit (benötigt für Paketprüfungen)...${NC}"
      emerge --quiet app-portage/gentoolkit
    fi
    ;;
  freebsd)
    PM_UPDATE="pkg update"
    PM_INSTALL="pkg install -y"
    PM_QUERY="pkg info"
    CHECK_INSTALLED_STATUS=""
    ;;
  *)
    echo -e "${RED}Distribution $DISTRO wird nicht unterstützt.${NC}"
    exit 1
    ;;
esac

# 4. Paketmanager updaten
echo -e "${GRAY}Aktualisiere Paketquellen...${NC}"
eval "$PM_UPDATE"

# 5. Feste Paketliste (nur Flatpak, kein snapd)
PACKAGES_TO_INSTALL=("flatpak")  # Nur flatpak wird installiert, niemals snapd

# 6. Pakete installieren
for package in "${PACKAGES_TO_INSTALL[@]}"; do
  echo -e "${GRAY}Prüfe, ob $package installiert ist...${NC}"
  
  if [ "$package" = "flatpak" ]; then
    if command -v flatpak >/dev/null 2>&1; then
      echo -e "${GREEN}Flatpak bereits installiert.${NC}"
      continue
    fi
  fi

  if [ "$PM_QUERY" != "" ]; then
    if $PM_QUERY "$package" 2>/dev/null | grep -q "$CHECK_INSTALLED_STATUS"; then
      echo -e "${GREEN}$package ist bereits installiert.${NC}"
      continue
    fi
  fi

  echo -e "${GRAY}Installiere $package...${NC}"
  eval "$PM_INSTALL $package"
done

# 7. Flathub hinzufügen (nur einmal)
echo -e "${GRAY}Füge Flathub-Repository hinzu (falls noch nicht vorhanden)...${NC}"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 8. Flatpak-Apps installieren
FLATPAK_APPS=(
  "com.discordapp.Discord"
  "org.gimp.GIMP"
  "com.abisource.AbiWord"
  "org.blender.Blender"
  "net.lutris.Lutris"
  "org.kde.kdenlive"
  "com.obsproject.Studio"
  "org.feichtmeier.Musicpod"
  "sa.sy.bluerecorder"
  "org.flameshot.Flameshot"
  "com.usebottles.bottles"
)

for app in "${FLATPAK_APPS[@]}"; do
  echo -e "${GRAY}Prüfe Installation: $app...${NC}"
  if flatpak list | grep -q "$app"; then
    echo -e "${GREEN}$app ist bereits installiert.${NC}"
  else
    echo -e "${GRAY}Installiere $app...${NC}"
    flatpak install -y flathub "$app"
  fi
done

# 9. Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null
#
echo
echo -e "${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
