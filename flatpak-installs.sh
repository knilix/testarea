#!/bin/bash
# Maintener: @knilix
# --> Nur x64 Architektur!
# root user benötigt (su)
# Für Debian, Ubuntu, Arch, Fedora, Gentoo, FreeBSD, Alpine, Bazzite geeignet.
# Vorher erledigen: --> installieren von wget und zip 
# Discord, Gimp, Abiword, Blender, Lutris, Kdenlive, Studio, Musocpod, Bluerecorder, Flameshot, Bottles
# Es wird geprüft, ob Flatpak installiert ist. Wenn nicht, wird es installiert.
# Es wird geprüft, ob die zu installierenden Flatpak-Apps schon per Snap oder Nativ installiert sind. Wenn ja, wird die Installation der jeweiligen Flatpak-App übersprungen.
# Warnhinweise, die nur informativ sind und keinerlei Einfluss auf die Funktion der jeweiligen App haben, z.B. weil KDE statt Gnome verwendet wird, werden ausgeblendet.

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
elif [ -f /etc/os-release ] && grep -iq "bazzite" /etc/os-release; then
  DISTRO="bazzite"
else
  echo -e "${RED}Konnte die Distribution nicht erkennen.${NC}"
  exit 1
fi

echo -e "${GREEN}Distribution erkannt: $DISTRO${NC}"

# 3. Flatpak Installation sicherstellen
if ! command -v flatpak >/dev/null 2>&1; then
  echo -e "${GRAY}Flatpak ist nicht installiert. Installiere es...${NC}"
  if [[ "$DISTRO" == "bazzite" ]]; then
    echo -e "${GREEN}Auf Bazzite basiert, Flatpak sollte vorinstalliert sein.${NC}"
  else
    # Für andere Distributionen
    case "$DISTRO" in
      debian|ubuntu)
        apt update && apt install -y flatpak
        ;;
      arch)
        pacman -S --noconfirm flatpak
        ;;
      fedora)
        dnf install -y flatpak
        ;;
      alpine)
        apk add flatpak
        ;;
      gentoo)
        emerge --quiet app-eselect/eselect-repository
        emerge --quiet flatpak
        ;;
      freebsd)
        pkg install -y flatpak
        ;;
      *)
        echo -e "${RED}Unbekannte Distribution für Flatpak-Installation.${NC}"
        exit 1
        ;;
    esac
  fi
fi

# 4. Flathub hinzufügen (nur einmal)
echo -e "${GRAY}Füge Flathub-Repository hinzu (falls noch nicht vorhanden)...${NC}"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 5. Flatpak-Apps installieren
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

# 6. Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null
#
echo
echo -e "${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
