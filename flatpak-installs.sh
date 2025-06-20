#!/bin/bash
 # Maintener: @knilix
 #
 # --> Only test - only x64 !
 #
 # root user benötigt (su)
 #
 # Für Debian, Ubuntu, Arch, Fedora, Gentoo, FreeBSD, Alpine, CachyOS, Bazzite, Nitrux geeignet.
 # Vorher erledigen: 
 # - installieren von wget und zip 
 #
 # Es werden mit diesem Script Flatpak und folgende Apps installiert: Discord, Gimp, Blender, Kdenlive, OBSStudio, Misicpod, Flameshot, Bottles, ProtonPlus, 
 # Clapgrep, Filelight, Flatseal, Gearlever, Gimp, Photoolibre, Protontricks, Warehouse, WineZGUI, NotepadNext, Termius.
 # Es wird geprüft, ob Flatpak installiert ist. Wenn nicht, wird es installiert.
 # Es wird geprüft of die zu installierenden Flatpak-Apps schon per Snap oder Nativ installiert sind. Wenn ja, wird die Installation der jeweiligen Flatpak-App übersprungen.
 # Warnhinweise, die nur informativ sind und keinerlei Einfluss auf die Funktion der jeweiligen App haben, z.B. weil KDE statt Gnome verwendet wird, werden ausgeblendet.
 #
 # root user required (su)
 #
 # Suitable for Debian, Ubuntu, Arch, Fedora, Gentoo, FreeBSD, Alpine, CachyOS, Bazzite, Nitrux.
 # Do it beforehand:
 # - install wget and zip
 #
 # This script installs Flatpak and the following apps: Discord, Gimp, Blender, Lutris, Kdenlive, OBSStudio, Misicpod, BlueRecorder, Flameshot, Bottles, ProtonPlus, Clapgrep, Filelight,
 # Flatseal, Gearlever, Gimp, Photoolibre, Protontricks, Warehouse, WineZGUI, NotepadNext, Termius.
 # The system checks whether Flatpak is installed. If not, it is installed.
 # The system checks whether the Flatpak apps to be installed are already installed via Snap or Native. If yes, the installation of the respective Flatpak app is skipped.
 # Warnings that are only informative and have no influence on the function of the respective app, e.g. because KDE is used instead of Gnome, are hidden.
 #
 ################################################################################################################################################################################################################
 #
 # download and unzip: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/flatpak-installs.sh
 # execute (unique): cd /opt/scriptfiles/testarea-main && ./flatpak-installs.sh
 #
 #################################################################################################################################################################################################################
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
   "org.blender.Blender"
   "org.kde.kdenlive"
   "com.obsproject.Studio"
   "org.feichtmeier.Musicpod"
   "org.flameshot.Flameshot"
   "com.usebottles.bottles"
   "com.vysp3r.ProtonPlus"
   "de.leopoldluley.Clapgrep"
   "org.kde.filelight"
   "com.github.tchx84.Flatseal"
   "it.mijorus.gearlever"
   "me.ahola.aphototoollibre"
   "com.github.Matoking.protontricks"
   "io.github.flattool.Warehouse"
   "io.github.fastrizwaan.WineZGUI"
   "com.github.dail8859.NotepadNext"
   "com.termius.Termius"
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
