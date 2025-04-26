#!/bin/bash
# Maintener: @knilix
# Only test
#
# root user benötigt (su)
#
# Für Debian, Ubuntu, Arch, Fedora, Gentoo und Alpine geeignet.
# Vorher erledigen: 
# - installieren von wget und zip 
#
# Es wird geprüft, ob Flatpak installiert ist. Wenn nicht, wird es installiert.
# Es wird geprüft of die zu installierenden Flatpak-Apps schon per Snap oder Nativ installiert sind. Wenn ja, wird die Installation der jeweiligen Flatpak-App übersprungen.
# Warnhinweise, die nur informativ sind und keinerlei Einfluss auf die Funktion der jeweiligen App haben, z.B. weil KDE statt Gnome verwendet wird, werden ausgeblendet.
#
#
# root user required (su)
#
# Suitable for Debian, Ubuntu, Arch, Fedora, Gentoo and Alpine.
# Do it beforehand:
# - install wget and zip
#
# The system checks whether Flatpak is installed. If not, it is installed.
# The system checks whether the Flatpak apps to be installed are already installed via Snap or Native. If yes, the installation of the respective Flatpak app is skipped.
# Warnings that are only informative and have no influence on the function of the respective app, e.g. because KDE is used instead of Gnome, are hidden.
#
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

# 1. Architektur prüfen
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
  echo -e "${RED}Nur x64-Architekturen werden unterstützt (aktuell: $ARCH).${NC}"
  exit 1
fi

# 2. Distribution erkennen
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
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

# 3. Paketmanager und Befehle bestimmen
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
    
    # Prüfen ob equery verfügbar ist
    if ! command -v equery >/dev/null 2>&1; then
      echo -e "${GRAY}Installiere gentoolkit (benötigt für Paketprüfungen)...${NC}"
      emerge --quiet app-portage/gentoolkit
    fi
    ;;
  *)
    echo -e "${RED}Distribution $DISTRO wird nicht unterstützt.${NC}"
    exit 1
    ;;
esac

# 4. Paketmanager Existenz prüfen
PM_BIN=$(echo "$PM_INSTALL" | awk '{print $1}')
if ! command -v "$PM_BIN" >/dev/null 2>&1; then
  echo -e "${RED}Paketmanager $PM_BIN ist nicht vorhanden. Skript abgebrochen.${NC}"
  exit 1
fi

# 5. Feste Paketliste
PACKAGES_TO_INSTALL=("flatpak" "snapd")

installed_packages=()
skipped_packages=()
failed_packages=()

# 6. Paketquellen updaten
echo -e "${GRAY}Update der Paketquellen...${NC}"
eval "$PM_UPDATE"

# 7. Pakete installieren
for PACKAGE in "${PACKAGES_TO_INSTALL[@]}"; do
  echo -n -e "${GRAY}Prüfe Paket $PACKAGE... ${NC}"

  # Überprüfen, ob Snap installiert ist
  if command -v snap >/dev/null 2>&1; then
    if snap list | grep -q "$PACKAGE"; then
      echo -e "${YELLOW}$PACKAGE bereits als Snap installiert. Überspringe.${NC}"
      skipped_packages+=("$PACKAGE")
      continue
    fi
  fi

  # Überprüfen, ob das Paket bereits als Native-Paket installiert wurde
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    STATUS=$($PM_QUERY "$PACKAGE" 2>/dev/null || true)
    if [[ "$STATUS" == "$CHECK_INSTALLED_STATUS" ]]; then
      echo -e "${YELLOW}bereits als Native-Paket installiert. Überspringe.${NC}"
      skipped_packages+=("$PACKAGE")
      continue
    fi
  else
    if $PM_QUERY "$PACKAGE" >/dev/null 2>&1; then
      echo -e "${YELLOW}bereits als Native-Paket installiert. Überspringe.${NC}"
      skipped_packages+=("$PACKAGE")
      continue
    fi
  fi

  # Snapd wird nicht neu installiert, wenn Snap nicht vorhanden
  if [ "$PACKAGE" == "snapd" ] && ! command -v snap >/dev/null 2>&1; then
    echo -e "${YELLOW}Snapd ist nicht installiert. Überspringe Snapd-Installation.${NC}"
    skipped_packages+=("$PACKAGE")
    continue
  fi

  # Installieren
  echo -e "${GRAY}nicht installiert. Installiere...${NC}"
  if eval "$PM_INSTALL $PACKAGE"; then
    echo -e "${GREEN}$PACKAGE erfolgreich installiert.${NC}"
    installed_packages+=("$PACKAGE")
  else
    echo -e "${RED}Fehler beim Installieren von $PACKAGE.${NC}"
    failed_packages+=("$PACKAGE")
  fi
done

# 8. Zusammenfassung
echo
echo -e "${GRAY}=== Zusammenfassung ===${NC}"
echo -e "${GREEN}Installiert: ${#installed_packages[@]}${NC}"
if [ ${#installed_packages[@]} -gt 0 ]; then
  echo -e " -> ${installed_packages[*]}"
fi
echo -e "${YELLOW}Übersprungen (bereits installiert): ${#skipped_packages[@]}${NC}"
if [ ${#skipped_packages[@]} -gt 0 ]; then
  echo -e " -> ${skipped_packages[*]}"
fi
echo -e "${RED}Fehlgeschlagen: ${#failed_packages[@]}${NC}"
if [ ${#failed_packages[@]} -gt 0 ]; then
  echo -e " -> ${failed_packages[*]}"
fi
echo -e "${GRAY}========================${NC}"

# 9. Flatpak-Remote hinzufügen
echo
if command -v flatpak >/dev/null 2>&1; then
  echo -e "${GRAY}Füge Flathub-Remote hinzu (falls noch nicht vorhanden)...${NC}"
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
else
  echo -e "${RED}Flatpak nicht verfügbar. Kann Flathub-Remote nicht hinzufügen.${NC}"
  exit 1
fi

# 10. Prüfen, ob ein Desktop-Environment läuft
if [[ "$XDG_SESSION_TYPE" == "x11" || "$XDG_SESSION_TYPE" == "wayland" ]]; then
  echo
  echo -e "${GRAY}Grafische Sitzung erkannt ($XDG_SESSION_TYPE). Installiere dconf-Pakete für bessere Flatpak-Unterstützung...${NC}"

  case "$DISTRO" in
    debian|ubuntu)
      eval "$PM_INSTALL dconf-cli dconf-service"
      ;;
    arch|fedora|alpine|gentoo)
      eval "$PM_INSTALL dconf"
      ;;
    *)
      echo -e "${YELLOW}Unbekannte Distribution, überspringe dconf-Installation.${NC}"
      ;;
  esac

  if command -v dconf >/dev/null 2>&1; then
    echo -e "${GRAY}Führe dconf update aus...${NC}"
    sudo mkdir -p /etc/dconf/db/local.d
    sudo dconf update
  fi
else
  echo
  echo -e "${YELLOW}Keine grafische Sitzung erkannt. Überspringe dconf-Installation.${NC}"
fi

# 11. Flatpak-Apps installieren
echo
echo -e "${GRAY}Installiere Flatpak-Anwendungen...${NC}"

FLATPAK_APPS=(
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

for APP in "${FLATPAK_APPS[@]}"; do
  echo -e "${GRAY}Installiere $APP...${NC}"
  flatpak install -y flathub "$APP" 2> >(grep -v 'dconf-WARNING' >&2)
done

# 12. Abschlussmeldung
echo
echo -e "${GREEN}✅ Alle Aufgaben abgeschlossen.${NC}"

# 13. Aufräumen
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

exit 0
