# Funktion zum Prüfen der Internetverbindung
check_internet_connection() {
  echo -e "${GRAY}Prüfe Internetverbindung...${NC}"
  
  # Verschiedene Hosts zum Testen der Verbindung
  for host in "google.com" "cloudflare.com" "1.1.1.1"; do
    if ping -c 1 -W 3 $host >/dev/null 2>&1; then
      echo -e "${GREEN}Internetverbindung ist verfügbar.${NC}"
      return 0
    fi
  done
  
  echo -e "${RED}Keine Internetverbindung verfügbar!${NC}"
  
  # Prüfe DNS-Einstellungen
  echo -e "${GRAY}Prüfe DNS-Konfiguration...${NC}"
  
  if [ -f /etc/resolv.conf ]; then
    echo -e "${YELLOW}Aktuelle DNS-Server:${NC}"
    grep "nameserver" /etc/resolv.conf || echo -e "${RED}Keine Nameserver gefunden!${NC}"
  else
    echo -e "${RED}Datei /etc/resolv.conf nicht gefunden!${NC}"
  fi
  
  echo -e "${YELLOW}Empfehlung: Versuche, die DNS-Server manuell zu konfigurieren, z.B. mit:${NC}"
  echo -e "${GRAY}echo 'nameserver 8.8.8.8' > /etc/resolv.conf${NC}"
  echo -e "${GRAY}echo 'nameserver 1.1.1.1' >> /etc/resolv.conf${NC}"
  
  return 1
}#!/bin/bash
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

# Internetverbindung prüfen vor dem Fortfahren
check_internet_connection
INTERNET_AVAILABLE=$?

# 4. Flathub hinzufügen (nur einmal) mit Netzwerkprüfung
if [ $INTERNET_AVAILABLE -eq 0 ]; then
  echo -e "${GRAY}Prüfe Netzwerkverbindung zu Flathub...${NC}"
  if ping -c 1 -W 3 flathub.org >/dev/null 2>&1; then
    echo -e "${GRAY}Füge Flathub-Repository hinzu (falls noch nicht vorhanden)...${NC}"
    if ! flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
      echo -e "${RED}Fehler beim Hinzufügen des Flathub-Repositories. Überprüfe die Netzwerkverbindung.${NC}"
      echo -e "${YELLOW}Versuche es mit einer alternativen Methode...${NC}"
      # Manueller Download der Repo-Datei als Fallback
      if wget -q --timeout=10 -O /tmp/flathub.flatpakrepo https://flathub.org/repo/flathub.flatpakrepo; then
        flatpak remote-add --if-not-exists flathub /tmp/flathub.flatpakrepo
        rm /tmp/flathub.flatpakrepo
      else
        echo -e "${RED}Konnte das Flathub-Repository nicht hinzufügen. Installationen werden wahrscheinlich fehlschlagen.${NC}"
      fi
    fi
  else
    echo -e "${RED}Keine Verbindung zu Flathub möglich. Prüfe DNS-Einstellungen oder Proxy-Konfiguration.${NC}"
  fi
else
  echo -e "${RED}Keine Internetverbindung verfügbar. Überprüfe Netzwerkeinstellungen.${NC}"
  echo -e "${YELLOW}Das Skript wird versuchen, mit offline vorhandenen Paketen fortzufahren.${NC}"
fi

# Prüfe, ob Flathub-Repository hinzugefügt wurde
if ! flatpak remotes | grep -q "flathub"; then
  echo -e "${RED}Warnung: Flathub-Repository ist nicht verfügbar. Die meisten Installationen werden fehlschlagen.${NC}"
  echo -e "${YELLOW}Möchtest du trotzdem fortfahren? (J/n)${NC}"
  read -r answer
  if [[ "$answer" =~ ^[Nn]$ ]]; then
    echo -e "${RED}Installation abgebrochen.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}Flathub-Repository erfolgreich eingerichtet.${NC}"
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
    if [ $INTERNET_AVAILABLE -eq 0 ] && flatpak remotes | grep -q "flathub"; then
      echo -e "${GRAY}Installiere $app_name als Flatpak...${NC}"
      if ! flatpak install -y flathub "$app_id"; then
        echo -e "${RED}Installation von $app_name fehlgeschlagen.${NC}"
        # Fallback-Methode: Versuche alternative Installation
        case "$DISTRO" in
          debian|ubuntu)
            echo -e "${YELLOW}Versuche native Installation über apt...${NC}"
            if apt-cache search "^$app_name$" >/dev/null 2>&1; then
              apt install -y "$app_name"
            else
              echo -e "${RED}$app_name ist nicht als natives Paket verfügbar.${NC}"
            fi
            ;;
          *)
            echo -e "${RED}Überspringe $app_name.${NC}"
            ;;
        esac
      fi
    else
      # Wenn keine Internetverbindung oder Flathub nicht verfügbar ist, versuche native Installation
      echo -e "${YELLOW}Flathub nicht verfügbar. Versuche native Installation von $app_name...${NC}"
      case "$DISTRO" in
        debian|ubuntu)
          if apt-cache search "^$app_name$" >/dev/null 2>&1; then
            apt install -y "$app_name"
          else
            echo -e "${RED}$app_name ist nicht als natives Paket verfügbar.${NC}"
          fi
          ;;
        arch)
          if pacman -Ss "^$app_name$" >/dev/null 2>&1; then
            pacman -S --noconfirm "$app_name"
          else
            echo -e "${RED}$app_name ist nicht als natives Paket verfügbar.${NC}"
          fi
          ;;
        fedora)
          if dnf search "$app_name" >/dev/null 2>&1; then
            dnf install -y "$app_name"
          else
            echo -e "${RED}$app_name ist nicht als natives Paket verfügbar.${NC}"
          fi
          ;;
        *)
          echo -e "${RED}Keine Installationsmethode für $app_name verfügbar.${NC}"
          ;;
      esac
    fi
  else
    echo -e "${YELLOW}Überspringe Installation von $app_name, da bereits installiert.${NC}"
  fi
done

# 7. Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

echo
echo -e "${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
