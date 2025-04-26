#!/bin/bash
# Maintener: @knilix
# Only test
#
# root user required (su)
#
# Für Debian, Ubuntu, Arch, Fedora und alpine geeignet.
# Es wird geprüft, ob Flatpak installiert ist. Wenn nicht, wird es installiert.
# Es wird geprüft of die zu installierenden Flatpak-Apps schon per Snap oder Nativ installiert sind. Wenn ja, wird die Installation der jeweiligen Flatpak-App übersprungen.
# Warnhinweise, die nur informativ sind und keinerlei Einfluss auf die Funktion der jeweiligen App haben, z.B. weil KDE statt Gnome verwendet wird, werden ausgeblendet.
#
#
# Suitable for Debian, Ubuntu, Arch, Fedora and alpine.
# The system checks whether Flatpak is installed. If not, it is installed.
# The system checks whether the Flatpak apps to be installed are already installed via Snap or Native. If yes, the installation of the respective Flatpak app is skipped.
# Warnings that are only informative and have no influence on the function of the respective app, e.g. because KDE is used instead of Gnome, are hidden.
#
#
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
  *)
    echo "Distribution $DISTRO wird nicht unterstützt."
    exit 1
    ;;
esac

# 4. Paketmanager Existenz prüfen
PM_BIN=$(echo "$PM_INSTALL" | awk '{print $1}')
if ! command -v "$PM_BIN" >/dev/null 2>&1; then
  echo "Paketmanager $PM_BIN ist nicht vorhanden. Skript abgebrochen."
  exit 1
fi

# 5. Feste Paketliste
PACKAGES_TO_INSTALL=("flatpak" "snapd")

# Listen für Zusammenfassung
installed_packages=()
skipped_packages=()
failed_packages=()

# 6. Paketquellen updaten
echo "Update der Paketquellen..."
eval "$PM_UPDATE"

# 7. Pakete installieren
for PACKAGE in "${PACKAGES_TO_INSTALL[@]}"; do
  echo -n "Prüfe Paket $PACKAGE... "

  # Überprüfen, ob das Paket bereits mit Snap installiert wurde
  if command -v snap >/dev/null 2>&1; then
    if snap list | grep -q "$PACKAGE"; then
      echo "$PACKAGE bereits als Snap installiert. Überspringe."
      skipped_packages+=("$PACKAGE")
      continue
    fi
  fi

  # Überprüfen, ob das Paket bereits als Native-Paket installiert wurde
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    STATUS=$($PM_QUERY "$PACKAGE" 2>/dev/null || true)
    if [[ "$STATUS" == "$CHECK_INSTALLED_STATUS" ]]; then
      echo "bereits als Native-Paket installiert. Überspringe."
      skipped_packages+=("$PACKAGE")
      continue
    fi
  else
    if $PM_QUERY "$PACKAGE" >/dev/null 2>&1; then
      echo "bereits als Native-Paket installiert. Überspringe."
      skipped_packages+=("$PACKAGE")
      continue
    fi
  fi

  # Wenn Snapd nicht installiert ist, überspringen wir es
  if [ "$PACKAGE" == "snapd" ] && ! command -v snap >/dev/null 2>&1; then
    echo "Snapd ist nicht installiert. Überspringe Snapd-Installation."
    skipped_packages+=("$PACKAGE")
    continue
  fi

  # Wenn nichts gefunden, dann installieren
  echo "nicht installiert. Installiere..."
  if eval "$PM_INSTALL $PACKAGE"; then
    echo "$PACKAGE erfolgreich installiert."
    installed_packages+=("$PACKAGE")
  else
    echo "Fehler beim Installieren von $PACKAGE."
    failed_packages+=("$PACKAGE")
  fi
done

# 8. Zusammenfassung
echo
echo "=== Zusammenfassung ==="
echo "Installiert: ${#installed_packages[@]}"
if [ ${#installed_packages[@]} -gt 0 ]; then
  echo " -> ${installed_packages[*]}"
fi
echo "Übersprungen (bereits installiert): ${#skipped_packages[@]}"
if [ ${#skipped_packages[@]} -gt 0 ]; then
  echo " -> ${skipped_packages[*]}"
fi
echo "Fehlgeschlagen: ${#failed_packages[@]}"
if [ ${#failed_packages[@]} -gt 0 ]; then
  echo " -> ${failed_packages[*]}"
fi
echo "========================"

# 9. Flatpak-Remote hinzufügen
echo
if command -v flatpak >/dev/null 2>&1; then
  echo "Füge Flathub-Remote hinzu (falls noch nicht vorhanden)..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
else
  echo "Flatpak nicht verfügbar. Kann Flathub-Remote nicht hinzufügen."
  exit 1
fi

# 10. Prüfen, ob ein Desktop-Environment läuft
if [[ "$XDG_SESSION_TYPE" == "x11" || "$XDG_SESSION_TYPE" == "wayland" ]]; then
  echo
  echo "Grafische Sitzung erkannt ($XDG_SESSION_TYPE). Installiere dconf-Pakete für bessere Flatpak-Unterstützung..."

  case "$DISTRO" in
    debian|ubuntu)
      eval "$PM_INSTALL dconf-cli dconf-service"
      ;;
    arch)
      eval "$PM_INSTALL dconf"
      ;;
    fedora)
      eval "$PM_INSTALL dconf"
      ;;
    alpine)
      eval "$PM_INSTALL dconf"
      ;;
    *)
      echo "Unbekannte Distribution, überspringe dconf-Installation."
      ;;
  esac

  # Sicherstellen, dass dconf-Datenbank aktualisiert wird
  if command -v dconf >/dev/null 2>&1; then
    echo "Führe dconf update aus..."
    sudo mkdir -p /etc/dconf/db/local.d
    sudo dconf update
  fi
else
  echo
  echo "Keine grafische Sitzung erkannt. Überspringe dconf-Installation."
fi

# 11. Flatpak-Apps installieren
echo
echo "Installiere Flatpak-Anwendungen..."

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
  echo "Installiere $APP..."
  flatpak install -y flathub "$APP" 2> >(grep -v 'dconf-WARNING' >&2)
done

# 12. Aufräumen
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip

#clear

# 13. Abschlussmeldung
echo
echo
echo "✅ Alle Aufgaben abgeschlossen."
echo
echo

exit 0
