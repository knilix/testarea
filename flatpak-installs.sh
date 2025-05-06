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

# 3. Prüfen ob Flatpak installiert ist und installieren falls nicht
if ! command -v flatpak >/dev/null 2>&1; then
  echo -e "${GRAY}Flatpak ist nicht installiert. Installiere es...${NC}"
  if [[ "$DISTRO" == "bazzite" ]]; then
    echo -e "${GREEN}Auf Bazzite basiert, Flatpak sollte vorinstalliert sein.${NC}"
  else
    # Für andere Distributionen
    case "$DISTRO" in
      debian|ubuntu)
        apt update && apt install -y flatpak gnome-software-plugin-flatpak
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
else
  echo -e "${GREEN}Flatpak ist bereits installiert.${NC}"
fi

# Nach der Installation von Flatpak neustarten, wenn nötig (besonders für Ubuntu)
if [ "$DISTRO" = "ubuntu" ] || [ "$DISTRO" = "debian" ]; then
  echo -e "${YELLOW}Hinweis: Auf manchen Ubuntu/Debian-Systemen kann ein Neustart nach der ersten Flatpak-Installation nötig sein.${NC}"
  echo -e "${YELLOW}Falls Fehler auftreten, bitte das System neustarten und das Skript erneut ausführen.${NC}"
fi

# 4. Flathub hinzufügen (nur einmal) mit Netzwerkprüfung
echo -e "${GRAY}Prüfe Netzwerkverbindung zu Flathub...${NC}"
if ping -c 1 flathub.org >/dev/null 2>&1; then
  echo -e "${GRAY}Füge Flathub-Repository hinzu (falls noch nicht vorhanden)...${NC}"
  if ! flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
    echo -e "${RED}Fehler beim Hinzufügen des Flathub-Repositories. Überprüfe die Netzwerkverbindung.${NC}"
    echo -e "${YELLOW}Versuche es mit einer alternativen Methode...${NC}"
    # Manueller Download der Repo-Datei als Fallback
    wget -q -O /tmp/flathub.flatpakrepo https://flathub.org/repo/flathub.flatpakrepo
    if [ -f /tmp/flathub.flatpakrepo ]; then
      flatpak remote-add --if-not-exists flathub /tmp/flathub.flatpakrepo
      rm /tmp/flathub.flatpakrepo
    else
      echo -e "${RED}Konnte das Flathub-Repository nicht hinzufügen. Installationen werden wahrscheinlich fehlschlagen.${NC}"
    fi
  fi
else
  echo -e "${RED}Keine Verbindung zu Flathub möglich. Überprüfe deine Internetverbindung.${NC}"
  echo -e "${YELLOW}Prüfe, ob Flathub bereits als Remote konfiguriert ist...${NC}"
  if ! flatpak remotes | grep -q "flathub"; then
    echo -e "${RED}Flathub ist nicht konfiguriert und kann nicht hinzugefügt werden. Installationen werden fehlschlagen.${NC}"
    echo -e "${YELLOW}Das Skript wird fortgesetzt, aber Installationen werden wahrscheinlich fehlschlagen.${NC}"
  else
    echo -e "${GREEN}Flathub ist bereits als Remote konfiguriert.${NC}"
  fi
fi

# 5. Prüffunktion für native und Snap-Installationen
is_app_installed() {
  app_name="$1"
  flatpak_id="$2"
  
  # Überprüfung auf native Installation (basierend auf häufigen Paketnamen)
  case "$app_name" in
    discord)
      native_pkgs="discord discord-bin discord-ptb discord-canary"
      ;;
    gimp)
      native_pkgs="gimp"
      ;;
    abiword)
      native_pkgs="abiword"
      ;;
    blender)
      native_pkgs="blender"
      ;;
    lutris)
      native_pkgs="lutris"
      ;;
    kdenlive)
      native_pkgs="kdenlive"
      ;;
    obs-studio)
      native_pkgs="obs-studio obs"
      ;;
    musicpod)
      native_pkgs="musicpod"
      ;;
    bluerecorder)
      native_pkgs="bluerecorder"
      ;;
    flameshot)
      native_pkgs="flameshot"
      ;;
    bottles)
      native_pkgs="bottles"
      ;;
    *)
      native_pkgs=""
      ;;
  esac
  
  # Prüfen auf native Installation je nach Distribution
  for pkg in $native_pkgs; do
    case "$DISTRO" in
      debian|ubuntu)
        if dpkg -l | grep -q "\\b$pkg\\b"; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      arch)
        if pacman -Q "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      fedora)
        if rpm -q "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      alpine)
        if apk info -e "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      gentoo)
        if qlist -I | grep -q "\\b$pkg\\b"; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      freebsd)
        if pkg info | grep -q "\\b$pkg\\b"; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
      bazzite)
        if rpm -q "$pkg" >/dev/null 2>&1; then
          echo -e "${GREEN}$app_name ist bereits nativ installiert.${NC}"
          return 0
        fi
        ;;
    esac
  done
  
  # Prüfen auf Snap-Installation, falls snap verfügbar ist
  if command -v snap >/dev/null 2>&1; then
    if snap list 2>/dev/null | grep -q "\\b$app_name\\b"; then
      echo -e "${GREEN}$app_name ist bereits als Snap installiert.${NC}"
      return 0
    fi
  fi
  
  # Prüfen auf Flatpak-Installation
  if flatpak list | grep -q "$flatpak_id"; then
    echo -e "${GREEN}$app_name ist bereits als Flatpak installiert.${NC}"
    return 0
  fi
  
  # App ist nicht installiert
  return 1
}

# 6. Flatpak-Apps installieren
declare -A APP_MAP=(
  ["com.discordapp.Discord"]="discord"
  ["org.gimp.GIMP"]="gimp"
  ["com.abisource.AbiWord"]="abiword"
  ["org.blender.Blender"]="blender"
  ["net.lutris.Lutris"]="lutris"
  ["org.kde.kdenlive"]="kdenlive"
  ["com.obsproject.Studio"]="obs-studio"
  ["org.feichtmeier.Musicpod"]="musicpod"
  ["sa.sy.bluerecorder"]="bluerecorder"
  ["org.flameshot.Flameshot"]="flameshot"
  ["com.usebottles.bottles"]="bottles"
)

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

for app_id in "${FLATPAK_APPS[@]}"; do
  app_name=${APP_MAP[$app_id]}
  echo -e "${GRAY}Prüfe Installation: $app_name...${NC}"
  
  if ! is_app_installed "$app_name" "$app_id"; then
    echo -e "${GRAY}Installiere $app_name als Flatpak...${NC}"
    # Prüfe, ob Flathub als Remote verfügbar ist
    if flatpak remotes | grep -q "flathub"; then
      if ! flatpak install -y flathub "$app_id"; then
        echo -e "${RED}Installation von $app_name fehlgeschlagen. Überspringe.${NC}"
      fi
    else
      echo -e "${RED}Flathub-Repository ist nicht verfügbar. Kann $app_name nicht installieren.${NC}"
    fi
  else
    echo -e "${YELLOW}Überspringe Installation von $app_name als Flatpak, da bereits installiert.${NC}"
  fi
done

# 7. Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

echo
echo -e "${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
